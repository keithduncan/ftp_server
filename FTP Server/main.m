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
#import "AFNetworkInMemoryFileSystem.h"

#pragma mark -

void server_main(void) {
	AFNetworkFTPServer *server = [AFNetworkFTPServer server];
	server.fileSystem = [[[AFNetworkInMemoryFileSystem alloc] init] autorelease];
	
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
