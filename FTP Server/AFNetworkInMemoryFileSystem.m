//
//  VirtualFileSystem.m
//  FTP Server
//
//  Created by Keith Duncan on 07/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkInMemoryFileSystem.h"

#import "CoreNetworking/CoreNetworking.h"

@interface AFNetworkInMemoryFileSystem ()
@property (assign, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSMutableDictionary *rootContainer;
@end

@implementation AFNetworkInMemoryFileSystem

@synthesize queue=_queue;

@synthesize rootContainer=_rootContainer;

- (id)init {
	self = [super init];
	if (self == nil) return nil;
	
	_queue = dispatch_queue_create("com.thirty-three.corenetworking.filesystem.memory", DISPATCH_QUEUE_CONCURRENT);
	
	_rootContainer = [[NSMutableDictionary alloc] init];
	
	return self;
}

- (void)dealloc {
	dispatch_release(_queue);
	
	[_rootContainer release];
	
	[super dealloc];
}

- (NSString *)_keyPathForUser:(NSString *)user path:(NSString *)path {
	NSParameterAssert(user != nil);
	NSParameterAssert(path != nil);
	
	NSMutableString *fullPath = [NSMutableString stringWithString:path];
	
	[fullPath replaceOccurrencesOfString:@"~/" withString:[NSString stringWithFormat:@"%@/", user] options:(NSStringCompareOptions)0 range:NSMakeRange(0, [fullPath length])];
	[fullPath replaceOccurrencesOfString:@"." withString:@"-" options:(NSStringCompareOptions)0 range:NSMakeRange(0, [fullPath length])];
	
	NSArray *replacements = [NSArray arrayWithObjects:
							 @"\012",
							 @"\015",
							 @"/",
							 nil];
	for (NSString *currentReplacemant in replacements) {
		[fullPath replaceOccurrencesOfString:currentReplacemant withString:@"." options:(NSStringCompareOptions)0 range:NSMakeRange(0, [fullPath length])];
	}
	
	if ([fullPath hasPrefix:@"."]) {
		fullPath = [NSMutableString stringWithString:[fullPath substringFromIndex:1]];
	}
	
	return fullPath;
}

- (id)_recursivelyDecomposeKeyPath:(NSString *)keyPath error:(NSError **)errorRef {
	id currentValue = [self rootContainer];
	
	NSEnumerator *keyPathEnumerator = [[keyPath componentsSeparatedByString:@"."] objectEnumerator];
	NSString *currentKeyPathComponent = nil;
	
	while ((currentKeyPathComponent = [keyPathEnumerator nextObject]) != nil) {
		currentValue = [currentValue valueForKey:currentKeyPathComponent];
		
		if (currentValue == nil || [currentValue isEqual:[NSNull null]]) {
			if (errorRef != NULL) {
				*errorRef = [NSError errorWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:nil];
			}
			return nil;
		}
	}
	
	return currentValue;
}

#warning change these to use dispatch_async and for AFNetworkFTPServer to serialise the file system response back to the respective connection's serial environment

- (void)makeContainerForUser:(NSString *)user atPath:(NSString *)path handler:(void (^)(BOOL (^)(NSError **)))handler {
	__block BOOL (^response)(NSError **) = nil;
	
	dispatch_sync([self queue], ^ {
		NSString *keyPath = [self _keyPathForUser:user path:path];
		
		NSString *containerKeyPath = nil, *newContainerName = nil;
		do {
			NSRange lastSeparator = [keyPath rangeOfString:@"." options:NSBackwardsSearch];
			if (lastSeparator.location == NSNotFound) {
				containerKeyPath = @"self";
				newContainerName = keyPath;
				break;
			}
			
			containerKeyPath = [keyPath substringToIndex:lastSeparator.location];
			newContainerName = [keyPath substringFromIndex:NSMaxRange(lastSeparator)];
		} while (0);
		
		id container = [self _recursivelyDecomposeKeyPath:containerKeyPath error:NULL];
		if (container == nil || ![container isKindOfClass:[NSDictionary class]]) {
			response = [^ BOOL (NSError **errorRef) {
				if (errorRef != NULL){
					*errorRef = [NSError errorWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:nil];
				}
				return NO;
			} copy];
			return;
		}
		
		id newContainer = [NSMutableDictionary dictionary];
		[container setValue:newContainer forKey:newContainerName];
		
		response = [^ BOOL (NSError **errorRef) {
			return YES;
		} copy];
	});
	response = [response autorelease];
	
	handler(response);
}

- (void)removeContainerForUser:(NSString *)user atPath:(NSString *)path handler:(void (^)(BOOL (^)(NSError **)))handler {
	__block BOOL (^response)(NSError **) = nil;
	
	dispatch_sync([self queue], ^ {
		if (!NO) {
			response = [^ BOOL (NSError **errorRef) {
				if (errorRef != NULL) {
					*errorRef = [NSError errorWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:nil];
				}
				return NO;
			} copy];
			return;
		}
		
		response = [^ BOOL (NSError **errorRef) {
			return YES;
		} copy];
	});
	response = [response autorelease];
	
	handler(response);
}

- (void)listContentsOfContainerForUser:(NSString *)user atPath:(NSString *)path handler:(void (^)(NSArray * (^)(NSError **)))handler {
	__block NSArray * (^response)(NSError **) = nil;
	
	dispatch_sync([self queue], ^ {
		if (!NO) {
			response = [^ NSArray * (NSError **errorRef) {
				if (errorRef != NULL) {
					*errorRef = [NSError errorWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:nil];
				}
				return nil;
			} copy];
			return;
		}
		
		NSMutableArray *contents = [NSMutableArray array];
		
		response = [^ NSArray * (NSError **errorRef) {
			return contents;
		} copy];
	});
	response = [response autorelease];
	
	handler(response);
}

- (NSInputStream *)readStreamForObjectWithUser:(NSString *)user path:(NSString *)path error:(NSError **)errorRef {
	if (errorRef != NULL) {
		*errorRef = [[NSError alloc] initWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:nil];
	}
	return nil;
}

- (NSOutputStream *)writeStreamForObjectWithUser:(NSString *)user path:(NSString *)path error:(NSError **)errorRef {
	if (errorRef != NULL) {
		*errorRef = [[NSError alloc] initWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:nil];
	}
	return nil;
}

@end
