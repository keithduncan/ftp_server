//
//  KDCameraServerController.m
//  Camera Server
//
//  Created by Keith Duncan on 17/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "KDCameraServerController.h"

#import "CameraServer-Functions.h"

@interface KDCameraServerController ()
@property (retain, nonatomic) id <AFVirtualFileSystem> fileSystem;
@end

@implementation KDCameraServerController

@synthesize fileSystem=_fileSystem;

- (id)initWithFileSystem:(id <AFVirtualFileSystem>)fileSystem {
	self = [self init];
	if (self == nil) return nil;
	
	_fileSystem = [fileSystem retain];
	
	return self;
}

- (void)dealloc {
	[_fileSystem release];
	
	[super dealloc];
}

- (CFHTTPMessageRef)networkServer:(AFHTTPServer *)server renderResourceForRequest:(CFHTTPMessageRef)request {
	NSString *requestMethod = [NSMakeCollectable(CFHTTPMessageCopyRequestMethod(request)) autorelease];
	
	NSSet *allowedMethods = [NSSet setWithObjects:AFHTTPMethodHEAD, AFHTTPMethodGET, nil];
	if (![allowedMethods containsObject:requestMethod]) {
		return NULL;
	}
	
	
	NSURL *requestURL = [NSMakeCollectable(CFHTTPMessageCopyRequestURL(request)) autorelease];
	
	NSString *requestPath = [requestURL path];
	
	NSArray *requestPathComponents = [requestPath pathComponents];
	if (![[requestPathComponents lastObject] isEqualToString:@"latest"]) {
		return NULL;
	}
	
	NSString *listPath = [[[requestPathComponents subarrayWithRange:NSMakeRange(0, [requestPathComponents count] - 1)] componentsJoinedByString:@"/"] stringByStandardizingPath];
	
	AFVirtualFileSystemRequestRead *listRequest = [[[AFVirtualFileSystemRequestRead alloc] initWithPath:listPath] autorelease];
	
	NSError *listError = nil;
	AFVirtualFileSystemResponse *listResponse = [self.fileSystem executeRequest:listRequest error:&listError];
	if (listResponse == nil) {
		return NULL;
	}
	if (listResponse.node.nodeType != AFVirtualFileSystemNodeTypeContainer) {
		return NULL;
	}
	
	NSSortDescriptor *numericSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"absolutePath" ascending:YES comparator:^ NSComparisonResult (id obj1, id obj2) {
		return [(NSString *)obj1 compare:(NSString *)obj2 options:NSNumericSearch];
	}];
	
	NSSet *children = listResponse.body;
	NSArray *sortedChildren = [children sortedArrayUsingDescriptors:@[ numericSortDescriptor ]];
	NSString *latestNodePath = [sortedChildren.lastObject absolutePath];
	
	AFVirtualFileSystemRequestRead *readRequest = [[[AFVirtualFileSystemRequestRead alloc] initWithPath:latestNodePath] autorelease];
	
	NSError *readError = nil;
	AFVirtualFileSystemResponse *readResponse = [self.fileSystem executeRequest:readRequest error:&readError];
	if (readResponse == nil) {
		return NULL;
	}
	if (readResponse.node.nodeType != AFVirtualFileSystemNodeTypeObject) {
		return NULL;
	}
	
	
	CFHTTPMessageRef response = AFHTTPMessageMakeResponseWithCode(AFHTTPStatusCodeOK);
	
	NSString *contentType = CameraServerContentTypeForFileSystemPath(readResponse.node.absolutePath);
	CFHTTPMessageSetHeaderFieldValue(response, (CFStringRef)AFHTTPMessageContentTypeHeader, (CFStringRef)contentType);
	
	if ([requestMethod isEqualToString:AFHTTPMethodHEAD]) {
		return response;
	}
	
	NSData *bodyData = CameraServerContentsOfInputStream(readResponse.body, NULL);
	if (bodyData == nil) {
		return NULL;
	}
	CFHTTPMessageSetBody(response, (CFDataRef)bodyData);
	
	return response;
}

@end
