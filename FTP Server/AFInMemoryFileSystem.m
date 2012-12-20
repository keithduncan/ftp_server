//
//  VirtualFileSystem.m
//  FTP Server
//
//  Created by Keith Duncan on 07/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFInMemoryFileSystem.h"

#import <libkern/OSAtomic.h>
#import <pthread.h>
#import "CoreNetworking/CoreNetworking.h"

#import "AFVirtualFileSystemNode+AFVirtualFileSystemPrivate.h"

@interface _AFInMemoryFileSystemNode : NSObject <NSLocking>

- (id)initWithName:(NSString *)name;

@property (readonly, copy, nonatomic) NSString *name;

@property (readonly, nonatomic) AFVirtualFileSystemNodeType nodeType;

- (void)lockExclusive;

@end

@implementation _AFInMemoryFileSystemNode {
	pthread_rwlock_t _lock;
}

- (id)initWithName:(NSString *)name {
	self = [self init];
	if (self == nil) return nil;
	
	_name = [name copy];
	
	int initLock = pthread_rwlock_init(&_lock, NULL);
	NSParameterAssert(initLock == 0);
	
	return self;
}

- (void)dealloc {
	[_name release];
	
	int deallocLock = pthread_rwlock_destroy(&_lock);
	NSParameterAssert(deallocLock == 0);
	
	[super dealloc];
}

- (AFVirtualFileSystemNodeType)nodeType {
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"subclass should implement selector" userInfo:nil];
}

- (void)lock {
	pthread_rwlock_rdlock(&_lock);
}

- (void)lockExclusive {
	pthread_rwlock_wrlock(&_lock);
}

- (void)unlock {
	pthread_rwlock_unlock(&_lock);
}

@end

@interface _AFInMemoryFileSystemContainer : _AFInMemoryFileSystemNode

/* Read */

- (NSSet *)children;
- (_AFInMemoryFileSystemNode *)childWithName:(NSString *)name;

/* Write */

- (void)addChild:(_AFInMemoryFileSystemNode *)child;
- (void)removeChild:(_AFInMemoryFileSystemNode *)child;

@end

@implementation _AFInMemoryFileSystemContainer {
	NSMutableDictionary *_children;
}

- (id)initWithName:(NSString *)name {
	self = [super initWithName:name];
	if (self == nil) return nil;
	
	_children = [[NSMutableDictionary alloc] initWithCapacity:1000000];
	
	return self;
}

- (void)dealloc {
	[_children release];
	
	[super dealloc];
}

- (AFVirtualFileSystemNodeType)nodeType {
	return AFVirtualFileSystemNodeTypeContainer;
}

/* Read */

- (NSSet *)children {
	return [NSSet setWithArray:[_children allValues]];
}

- (_AFInMemoryFileSystemNode *)childWithName:(NSString *)name {
	return [_children objectForKey:name];
}

/* Write */

- (void)addChild:(_AFInMemoryFileSystemNode *)child {
	[_children setObject:child forKey:child.name];
}

- (void)removeChild:(_AFInMemoryFileSystemNode *)child {
	[_children removeObjectForKey:child.name];
}

@end

@interface _AFInMemoryFileSystemObject : _AFInMemoryFileSystemNode

- (id)initWithName:(NSString *)name data:(NSData *)data;

@property (readonly, retain, nonatomic) NSData *data;

@end

@implementation _AFInMemoryFileSystemObject

@synthesize data=_data;

- (id)initWithName:(NSString *)name data:(NSData *)data {
	self = [self initWithName:name];
	if (self == nil) return nil;
	
	_data = [data retain];
	
	return self;
}

- (AFVirtualFileSystemNodeType)nodeType {
	return AFVirtualFileSystemNodeTypeObject;
}

@end

#pragma mark -

@interface _AFInMemoryFileSystemOutputStream : NSOutputStream

+ (id)outputStreamToFileSystem:(AFInMemoryFileSystem *)fileSystem updateRequest:(AFVirtualFileSystemRequestUpdate *)updateRequest;

@property (retain, nonatomic) AFInMemoryFileSystem *fileSystem;
@property (retain, nonatomic) AFVirtualFileSystemRequestUpdate *updateRequest;

@end

#pragma mark -

@interface AFInMemoryFileSystem ()
@property (assign, nonatomic) _AFInMemoryFileSystemContainer *root;
@property (assign, nonatomic) int64_t pendingTransactionCount;
@end

@interface AFInMemoryFileSystem ()
- (BOOL)_tryIncreasePendingTransactionCount;
- (void)_decrementPendingTransactionCount;
@end

@implementation AFInMemoryFileSystem

@synthesize root=_root;

- (id)init {
	self = [super init];
	if (self == nil) return nil;
	
	_root = [[_AFInMemoryFileSystemContainer alloc] initWithName:@"/"];
	
	_pendingTransactionCount = -1;
	
	return self;
}

- (void)dealloc {
	[_root release];
	
	[super dealloc];
}

- (BOOL)_tryMount {
	/*
		Note
		
		the file system must be unmounted for mounting to succeed
	 */
	return OSAtomicCompareAndSwap64Barrier(-1, 0, &_pendingTransactionCount);
}

- (BOOL)mount:(NSError **)errorRef {
	if (![self _tryMount]) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"Cannot mount while already mounted", @"AFInMemoryFileSystem mount from unknown state error description"),
			};
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeAlreadyMounted userInfo:errorInfo];
		}
		return NO;
	}
	return YES;
}

- (BOOL)_tryUnmount {
	/*
		Note
		
		there must be 0 outstanding transactions for unmounting to succeed
	 */
	return OSAtomicCompareAndSwap64Barrier(0, -1, &_pendingTransactionCount);
}

- (BOOL)unmount:(NSError **)errorRef {
	if (![self _tryUnmount]) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"Cannot unmount while node operations are pending", @"AFInMemoryFileSystem unmount pending transactions error description"),
			};
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeBusy userInfo:errorInfo];
		}
		return NO;
	}
	
	return YES;
}

- (BOOL)_tryIncreasePendingTransactionCount {
	int64_t volatile *pendingTransactionCountRef = &_pendingTransactionCount;
	while (1) {
		int64_t pendingTransactionCount = *pendingTransactionCountRef;
		if (pendingTransactionCount == -1) {
			return NO;
		}
		
		bool swap = OSAtomicCompareAndSwap64Barrier(pendingTransactionCount, pendingTransactionCount + 1, pendingTransactionCountRef);
		if (!swap) {
			continue;
		}
		
		return YES;
	}
}

- (void)_decrementPendingTransactionCount {
	OSAtomicDecrement64Barrier(&_pendingTransactionCount);
}

- (_AFInMemoryFileSystemNode *)_nodeWithPath:(NSString *)path {
	NSArray *pathComponents = [path pathComponents];
	if ([pathComponents count] == 0) {
		return NULL;
	}
	
	if (![pathComponents[0] isEqualToString:@"/"]) {
		return NULL;
	}
	
	_AFInMemoryFileSystemContainer *currentNode = self.root;
	if ([pathComponents count] == 1) {
		return currentNode;
	}
	else {
		NSArray *subpathComponents = [pathComponents subarrayWithRange:NSMakeRange(1, [pathComponents count] - 1)];
		
		for (NSString *currentPathComponent in subpathComponents) {
			if (![currentNode isKindOfClass:[_AFInMemoryFileSystemContainer class]]) {
				return nil;
			}
			
			[currentNode lock];
			_AFInMemoryFileSystemNode *child = [[[currentNode childWithName:currentPathComponent] retain] autorelease];
			[currentNode unlock];
			
			currentNode = (id)child;
		}
		
		return currentNode;
	}
}

- (_AFInMemoryFileSystemContainer *)_containerWithPath:(NSString *)path error:(NSError **)errorRef {
	_AFInMemoryFileSystemNode *container = [self _nodeWithPath:path];
	if (container == nil) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNoNodeExists userInfo:nil];
		}
		return nil;
	}
	
	if (![container isKindOfClass:[_AFInMemoryFileSystemContainer class]]) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotContainer userInfo:nil];
		}
		return nil;
	}
	
	return (id)container;
}

- (_AFInMemoryFileSystemObject *)_objectWithPath:(NSString *)path error:(NSError **)errorRef {
	NSString *containerPath = [path stringByDeletingLastPathComponent];
	_AFInMemoryFileSystemContainer *container = [self _containerWithPath:containerPath error:errorRef];
	if (container == NULL) {
		return NULL;
	}
	
	NSString *objectName = [path lastPathComponent];
	
	[container lock];
	_AFInMemoryFileSystemNode *object = [[[container childWithName:objectName] retain] autorelease];
	[container unlock];
	
	if (object == nil) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNoNodeExists userInfo:nil];
		}
		return nil;
	}
	
	if (![object isKindOfClass:[_AFInMemoryFileSystemObject class]]) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotObject userInfo:nil];
		}
		return nil;
	}
	
	return (id)object;
}

#warning ensure we can create and update child object nodes of the root node

- (AFVirtualFileSystemResponse *)executeRequest:(AFVirtualFileSystemRequest *)request error:(NSError **)errorRef {
	if ([request isKindOfClass:[AFVirtualFileSystemRequestCreate class]]) {
		AFVirtualFileSystemRequestCreate *createRequest = (id)request;
		NSString *createPath = createRequest.path;
		
		if ([createPath isEqualToString:@"/"]) {
			if (createRequest.nodeType != AFVirtualFileSystemNodeTypeContainer) {
				if (errorRef != NULL) {
					*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotObject userInfo:nil];
				}
				return nil;
			}
			
			AFVirtualFileSystemNode *responseNode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:@"/" nodeType:AFVirtualFileSystemNodeTypeContainer] autorelease];
			
			return [[[AFVirtualFileSystemResponse alloc] initWithNode:responseNode body:nil] autorelease];
		}
		
		NSString *objectName = [createPath lastPathComponent];
		
		_AFInMemoryFileSystemNode *newNode = nil;
		if (createRequest.nodeType == AFVirtualFileSystemNodeTypeContainer) {
			newNode = [[[_AFInMemoryFileSystemContainer alloc] initWithName:objectName] autorelease];
		}
		else if (createRequest.nodeType == AFVirtualFileSystemNodeTypeObject) {
			newNode = [[[_AFInMemoryFileSystemObject alloc] initWithName:objectName data:nil] autorelease];
		}
		else {
			if (errorRef != NULL) {
				*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeUnknownRequest userInfo:nil];
			}
			return nil;
		}
		
		NSString *containerPath = [createPath stringByDeletingLastPathComponent];
		_AFInMemoryFileSystemContainer *container = [self _containerWithPath:containerPath error:errorRef];
		if (container == nil) {
			return nil;
		}
		
		/*
			Note
			
			container lock taken to atomically search for a node with matching `nodeName` and create if absent
			
			mutual exclusion prevents concurrent callers from simultaneously creating a node with `nodeName` in the same container
		 */
		[container lockExclusive];
		
		_AFInMemoryFileSystemNode *existingChild = [[[container childWithName:objectName] retain] autorelease];
		if (existingChild != nil) {
			[container unlock];
			
			AFVirtualFileSystemNodeType existingChildNodeType = existingChild.nodeType;
			
			if (errorRef != NULL) {
				if (existingChildNodeType == createRequest.nodeType) {
					*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNodeExists userInfo:nil];
				}
				else if (existingChildNodeType == AFVirtualFileSystemNodeTypeObject) {
					*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotContainer userInfo:nil];
				}
				else if (existingChildNodeType == AFVirtualFileSystemNodeTypeContainer) {
					*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotObject userInfo:nil];
				}
				else {
					*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeUnknown userInfo:nil];
				}
			}
			return nil;
		}
		
		[container addChild:newNode];
		
		[container unlock];
		
		AFVirtualFileSystemNode *responseNode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:createPath nodeType:createRequest.nodeType] autorelease];
		
		return [[[AFVirtualFileSystemResponse alloc] initWithNode:responseNode body:nil] autorelease];
	}
	
	if ([request isKindOfClass:[AFVirtualFileSystemRequestRead class]]) {
		AFVirtualFileSystemRequestRead *readRequest = (id)request;
		NSString *readPath = readRequest.path;
		
		_AFInMemoryFileSystemNode *node = [self _nodeWithPath:readPath];
		if (node == nil) {
			if (errorRef != NULL) {
				*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNoNodeExists userInfo:nil];
			}
			return nil;
		}
		
		/*
			Note
			
			lock to atomically read the info of the tree node and it's children if it's a container
			
			if we only lock the node to get the info point, by the time we lock to get the children it could have been mutated from a container into an object
		 */
		AFVirtualFileSystemNode *responseNode = nil;
		id responseBody = nil;
		
		if ([node isKindOfClass:[_AFInMemoryFileSystemContainer class]]) {
			responseNode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:readPath nodeType:AFVirtualFileSystemNodeTypeContainer] autorelease];
			
			[node lock];
			NSSet *children = [NSSet setWithSet:[(_AFInMemoryFileSystemContainer *)node children]];
			[node unlock];
			
			NSMutableSet *vnodeChildren = [NSMutableSet setWithCapacity:[children count]];
			for (_AFInMemoryFileSystemNode *currentNode in children) {
				AFVirtualFileSystemNode *currentVnode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:[readPath stringByAppendingPathComponent:currentNode.name] nodeType:currentNode.nodeType] autorelease];
				[vnodeChildren addObject:currentVnode];
			}
			responseBody = vnodeChildren;
		}
		else if ([node isKindOfClass:[_AFInMemoryFileSystemObject class]]) {
			responseNode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:readPath nodeType:AFVirtualFileSystemNodeTypeObject] autorelease];
			responseBody = [NSInputStream inputStreamWithData:[(_AFInMemoryFileSystemObject *)node data]];
		}
		
		if (responseNode == nil) {
			if (errorRef != NULL) {
				*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeUnknown userInfo:nil];
			}
			return nil;
		}
		
		return [[[AFVirtualFileSystemResponse alloc] initWithNode:responseNode body:responseBody] autorelease];
	}
	
	if ([request isKindOfClass:[AFVirtualFileSystemRequestUpdate class]]) {
		AFVirtualFileSystemRequestUpdate *updateRequest = (id)request;
		NSString *updatePath = updateRequest.path;
		
		_AFInMemoryFileSystemObject *object = [self _objectWithPath:updatePath error:errorRef];
		if (object == nil) {
			return nil;
		}
		
#warning should we track 'open' child nodes in the parent directory node so that we can prevent them from being deleted
		
		AFVirtualFileSystemNode *responseNode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:updatePath nodeType:AFVirtualFileSystemNodeTypeObject] autorelease];
		NSOutputStream *responseBody = [_AFInMemoryFileSystemOutputStream outputStreamToFileSystem:self updateRequest:updateRequest];
		
		return [[[AFVirtualFileSystemResponse alloc] initWithNode:responseNode body:responseBody] autorelease];
	}
	
	if ([request isKindOfClass:[AFVirtualFileSystemRequestDelete class]]) {
		AFVirtualFileSystemRequestDelete *deleteRequest = (id)request;
		NSString *deletePath = deleteRequest.path;
		
		if ([deletePath isEqualToString:@"/"]) {
			if (errorRef != NULL) {
				*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeBusy userInfo:nil];
			}
			return nil;
		}
		
		NSString *containerPath = [deletePath stringByDeletingLastPathComponent];
		_AFInMemoryFileSystemContainer *container = [self _containerWithPath:containerPath error:errorRef];
		if (container == nil) {
			return nil;
		}
		
		NSString *nodeName = [deletePath lastPathComponent];
		
		[container lockExclusive];
		
		_AFInMemoryFileSystemNode *child = [[[container childWithName:nodeName] retain] autorelease];
		if (child == nil) {
			[container unlock];
			
			if (errorRef != NULL) {
				*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNoNodeExists userInfo:nil];
			}
			return nil;
		}
		
		if ([child isKindOfClass:[_AFInMemoryFileSystemContainer class]]) {
#warning should we prevent non empty container nodes from being deleted
		}
		
		[container removeChild:child];
		
		[container unlock];
		
		AFVirtualFileSystemNode *responseNode = [[[AFVirtualFileSystemNode alloc] initWithAbsolutePath:deletePath nodeType:child.nodeType] autorelease];
		
		return [[[AFVirtualFileSystemResponse alloc] initWithNode:responseNode body:nil] autorelease];
	}
	
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Cannot process file system request", nil, [NSBundle mainBundle], @"AFInMemoryFileSystem unknown request type error description"),
		};
		*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeUnknownRequest userInfo:errorInfo];
	}
	return nil;
}

@end

#pragma mark -

@interface _AFInMemoryFileSystemOutputStream ()
@property (retain, nonatomic) NSMutableData *data;

@property (assign, nonatomic) NSStreamStatus streamStatus;
@property (retain, nonatomic) NSError *streamError;

@property (assign, nonatomic) id <NSStreamDelegate> delegate;
@end

@implementation _AFInMemoryFileSystemOutputStream

@synthesize fileSystem=_fileSystem;
@synthesize updateRequest=_updateRequest;

@synthesize data=_data;

@synthesize streamStatus=_streamStatus;
@synthesize streamError=_streamError;

@synthesize delegate=_delegate;

+ (id)outputStreamToFileSystem:(AFInMemoryFileSystem *)fileSystem updateRequest:(AFVirtualFileSystemRequestUpdate *)updateRequest {
	_AFInMemoryFileSystemOutputStream *stream = [[[self alloc] init] autorelease];
	stream.fileSystem = fileSystem;
	stream.updateRequest = updateRequest;
	return stream;
}

- (id)init {
	self = [super init];
	if (self == nil) {
		return nil;
	}
	
	_data = [[NSMutableData alloc] init];
	
	return self;
}

- (void)dealloc {
	[_fileSystem release];
	[_updateRequest release];
	
	[_data release];
	[_streamError release];
	
	[super dealloc];
}

- (void)open {
	NSParameterAssert(self.streamStatus == NSStreamStatusNotOpen);
	
	BOOL increasePendingTransactionCount = [self.fileSystem _tryIncreasePendingTransactionCount];
	if (!increasePendingTransactionCount) {
		self.streamError = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNotMounted userInfo:nil];
		
		[self _setStreamStatusAndNotify:NSStreamStatusError];
		return;
	}
	
	[self _setStreamStatusAndNotify:NSStreamStatusOpen];
}

- (void)close {
	if (self.streamStatus == NSStreamStatusOpen) {
		NSError *swapError = nil;
		BOOL swap = [self _swap:&swapError];
		
		[self.fileSystem _decrementPendingTransactionCount];
		
		if (!swap) {
			self.streamError = swapError;
			[self _setStreamStatusAndNotify:NSStreamStatusError];
			return;
		}
	}
	
	[self _setStreamStatusAndNotify:NSStreamStatusClosed];
}

- (BOOL)_swap:(NSError **)errorRef {
	NSString *updatePath = self.updateRequest.path;
	
	NSString *containerPath = [updatePath stringByDeletingLastPathComponent];
	_AFInMemoryFileSystemContainer *container = [self.fileSystem _containerWithPath:containerPath error:errorRef];
	if (container == nil) {
		return NO;
	}
	
	NSString *objectName = [updatePath lastPathComponent];
	
	_AFInMemoryFileSystemObject *newObject = [[[_AFInMemoryFileSystemObject alloc] initWithName:objectName data:self.data] autorelease];
	_AFInMemoryFileSystemObject *oldObject = nil;
	
	[container lockExclusive];
	
	do {
		oldObject = (id)[[[container childWithName:objectName] retain] autorelease];
		if (oldObject == nil) {
			break;
		}
		
		[container addChild:newObject];
	} while (0);
	
	[container unlock];
	
	if (oldObject == nil) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFVirtualFileSystemErrorDomain code:AFVirtualFileSystemErrorCodeNoNodeExists userInfo:nil];
		}
		return NO;
	}
	
	return YES;
}

- (void)setDelegate:(id <NSStreamDelegate>)delegate {
	_delegate = (delegate ? : (id)self);
}

- (void)_setStreamStatusAndNotify:(NSStreamStatus)status {
	self.streamStatus = status;
	
	if (![self.delegate respondsToSelector:@selector(stream:handleEvent:)]) {
		return;
	}
	
	struct StatusToEvent {
		NSStreamStatus status;
		NSStreamEvent event;
	} statusToEventMap[] = {
		{ .status = NSStreamStatusOpen, .event = NSStreamEventOpenCompleted },
		{ .status = NSStreamStatusAtEnd, .event = NSStreamEventEndEncountered },
		{ .status = NSStreamStatusError, .event = NSStreamEventErrorOccurred },
	};
	for (NSUInteger idx = 0; idx < sizeof(statusToEventMap)/sizeof(*statusToEventMap); idx++) {
		if (statusToEventMap[idx].status != status) {
			continue;
		}
		
		[self.delegate stream:self handleEvent:statusToEventMap[idx].event];
		break;
	}
}

- (id)propertyForKey:(NSString *)key {
	return nil;
}

- (BOOL)setProperty:(id)property forKey:(NSString *)key {
	return NO;
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
	//nop
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
	//nop
}

- (BOOL)hasSpaceAvailable {
	return YES;
}

- (NSInteger)write:(uint8_t const *)buffer maxLength:(NSUInteger)maxLength {
	[self.data appendBytes:buffer length:maxLength];
	return maxLength;
}

@end
