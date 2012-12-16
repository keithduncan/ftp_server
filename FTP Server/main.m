//
//  main.m
//  FTP Server
//
//  Created by Keith Duncan on 05/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

#import "AFInMemoryFileSystem.h"
#import "AFNetworkFTPServer.h"
#import "AFNetworkHTTPFileSystemRenderer.h"

#pragma mark -

static id <AFVirtualFileSystem> MakeFileSystem(void) {
	id <AFVirtualFileSystem> fileSystem = [[[AFInMemoryFileSystem alloc] init] autorelease];
	
	BOOL (^createDirectoryWithPath)(NSString *, NSError **) = ^ BOOL (NSString *path, NSError **errorRef) {
		NSArray *pathComponents = [path pathComponents];
		for (NSUInteger componentIndex = 0; componentIndex < [pathComponents count]; componentIndex++) {
			NSString *partialPath = [[pathComponents subarrayWithRange:NSMakeRange(0, componentIndex + 1)] componentsJoinedByString:@"/"];
			
			AFVirtualFileSystemRequestCreate *createRequest = [[[AFVirtualFileSystemRequestCreate alloc] initWithPath:partialPath nodeType:AFVirtualFileSystemNodeTypeContainer] autorelease];
			
			NSError *createError = nil;
			id createResponse = [fileSystem executeRequest:createRequest error:&createError];
			if (createResponse == nil) {
				do {
					if ([[createError domain] isEqualToString:AFVirtualFileSystemErrorDomain] && [createError code] == AFVirtualFileSystemErrorCodeNodeExists) {
						break;
					}
					
					if (errorRef != NULL) {
						*errorRef = createError;
					}
					return NO;
				} while (0);
			}
			
			continue;
		}
		
		return YES;
	};
	
	NSArray *paths = [@"/Pictures/Cameras" stringsByAppendingPaths:@[ @"Kitchen", @"Server Room", @"Room 101", @"War Room", @"Library", @"Billiard Room" ]];
	
	for (NSString *currentPath in paths) {
		NSError *createError = nil;
		BOOL create = createDirectoryWithPath(currentPath, &createError);
		NSCParameterAssert(create);
	}
	
	NSCParameterAssert([fileSystem mount:NULL]);
	
	return fileSystem;
}

static AFNetworkFTPServer *StartFTPServer(id <AFVirtualFileSystem> fileSystem) {
	AFNetworkFTPServer *server = [AFNetworkFTPServer server];
	server.fileSystem = fileSystem;
	
	BOOL openSockets = [server openInternetSocketsWithSocketSignature:AFNetworkSocketSignatureInternetTCP scope:AFNetworkInternetSocketScopeGlobal port:2121 errorHandler:nil];
	NSCParameterAssert(openSockets);
	
	return server;
}

static AFNetworkServer *StartHTTPServer(id <AFVirtualFileSystem> fileSystem) {
	AFHTTPServer *server = [AFHTTPServer server];
	
	server.renderers = @[ [[[AFNetworkHTTPFileSystemRenderer alloc] initWithFileSystem:fileSystem] autorelease] ];
	
	BOOL openSockets = [server openInternetSocketsWithSocketSignature:AFNetworkSocketSignatureInternetTCP scope:AFNetworkInternetSocketScopeGlobal port:8080 errorHandler:nil];
	NSCParameterAssert(openSockets);
	
	return server;
}

void server_main(void) {
	id <AFVirtualFileSystem> newFileSystem = MakeFileSystem();
	
	__unused AFNetworkServer *ftpServer = StartFTPServer(newFileSystem);
	__unused AFNetworkServer *httpServer = StartHTTPServer(newFileSystem);
	
	CFRunLoopRun();
}

int main(int argc, const char **argv) {
	@autoreleasepool {
		server_main();
	}
    return 0;
}
