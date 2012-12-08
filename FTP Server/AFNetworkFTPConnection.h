//
//  AFNetworkFTPConnection.h
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkTelnetConnection.h"

@class AFNetworkFTPConnection;

@protocol AFNetworkFTPConnectionDelegate <AFTelnetConnectionDelegate>

- (void)connection:(AFNetworkFTPConnection *)connection dataConnectionDidReceiveError:(NSError *)error;
- (void)connectionDidReadDataToWriteStream:(AFNetworkFTPConnection *)connection;
- (void)connectionDidWriteDataFromReadStream:(AFNetworkFTPConnection *)connection;

@end

/*!
	\brief
	Telnet control channel with support for a data channel
 */
@interface AFNetworkFTPConnection : AFNetworkTelnetConnection

@property (assign, nonatomic) id <AFNetworkFTPConnectionDelegate> delegate;

/*
	PASV support
 */

/*!
	\brief
	Only the first connection to the data server is accepted and queued up.
	
	\details
	Throws an exception if there is already a data server open
 */
- (AFNetworkSocket *)openDataServerWithAddress:(NSData *)address error:(NSError **)errorRef;

/*!
	\brief
	Stop listening and terminate any ongoing data connection
 */
- (void)closeDataServer;

/*!
	\brief
	YES upon return from `openDataServerWithAddress:error:`
	NO upon return from `closeDataServer`
 */
@property (readonly, nonatomic) BOOL hasDataServer;

/*!
	\brief
	Wait for a timeout for a connection to appear on the listening socket, the first connection is accepted.
	The data server is automatically closed once a data connection is accepted or the timeout occurs.
 */
- (void)readFirstDataServerConnectionToWriteStream:(NSOutputStream *)outputStream;

/*!
	\brief
	Wait for a timeout for a connection to appear on the listening socket, the first connection is accepted.
	The data server is automatically closed once a data connection is accepted or the timeout occurs.
 */
- (void)writeFirstDataServerConnectionFromReadStream:(NSInputStream *)inputStream;

/*
	PORT support
 */

// Not implemented

@end
