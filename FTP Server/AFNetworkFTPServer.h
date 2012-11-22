//
//  AFNetworkFTPServer.h
//  FTP Server
//
//  Created by Keith Duncan on 06/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkVirtualFileSystem.h"

/*!
	\brief
	Responds to common FTP commands about the mounted file system.
 */
@interface AFNetworkFTPServer : AFNetworkServer

+ (id)server;

/*!
	\brief
	The server is oblivious to the type of the mounted file system.
 */
@property (retain, nonatomic) id <AFNetworkVirtualFileSystem> fileSystem;

@end
