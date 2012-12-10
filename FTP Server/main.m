//
//  main.m
//  FTP Server
//
//  Created by Keith Duncan on 05/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkFTPServer.h"
#import "AFInMemoryFileSystem.h"

#pragma mark -

id <AFVirtualFileSystem> MakeFileSystem(void) {
	id <AFVirtualFileSystem> fileSystem = [[[AFInMemoryFileSystem alloc] init] autorelease];
	
	void (^createDirectoryWithName)(NSString *) = ^ void (NSString *name) {
		AFVirtualFileSystemRequestCreate *createRequest = [[[AFVirtualFileSystemRequestCreate alloc] initWithPath:[@"/" stringByAppendingPathComponent:name] nodeType:AFVirtualFileSystemNodeTypeContainer] autorelease];
		id createResponse = [fileSystem executeRequest:createRequest error:NULL];
		NSCParameterAssert(createResponse != nil);
	};
	NSArray *directoryNames = @[ @"Applications", @"Developer", @"Library", @"System", @"Users" ];
	[directoryNames enumerateObjectsUsingBlock:(void (^)(id, NSUInteger, BOOL *))createDirectoryWithName];
	
	NSCParameterAssert([fileSystem mount:NULL]);
	
	return fileSystem;
}

void server_main(void) {
	id <AFVirtualFileSystem> newFileSystem = MakeFileSystem();
	
	AFNetworkFTPServer *server = [AFNetworkFTPServer server];
	server.fileSystem = newFileSystem;
	
	BOOL openSockets = [server openInternetSocketsWithSocketSignature:AFNetworkSocketSignatureInternetTCP scope:AFNetworkInternetSocketScopeGlobal port:5000 errorHandler:nil];
	NSCParameterAssert(openSockets);
	
	CFRunLoopRun();
}

int main(int argc, const char **argv) {
	@autoreleasepool {
		server_main();
	}
    return 0;
}
