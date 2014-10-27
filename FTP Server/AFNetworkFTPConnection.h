//
//  AFNetworkFTPConnection.h
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkTelnetConnection.h"

extern NSString *const AFNetworkFTPErrorDomain;

typedef NS_ENUM(NSInteger, AFNetworkFTPErrorCode) {
	AFNetworkFTPErrorCodeUnknown = 0,
	
	AFNetworkFTPErrorCodeNoDataServer = -1,
	AFNetworkFTPErrorCodeDataAlreadyEnqueued = -2,
};

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

/*!
	\brief
	Only the first connection to the data server is accepted and queued up, PASV support
	
	\details
	Throws an exception if there is already a data server open
 */
- (AFNetworkSocket *)startDataServerWithAddress:(NSData *)address error:(NSError **)errorRef;
/*!
	\brief
	Connect to a data server, PORT support
 */
- (BOOL)connectToDataServerWithAddress:(NSData *)address error:(NSError **)errorRef;

/*!
	\brief
	Stop listening / connecting (PASV / PORT) and terminate any ongoing data connection
 */
- (void)closeDataServer;

/*!
	\brief
	YES upon return from `startDataServerWithAddress:error:` and `connectToDataServerWithAddress:error:`
	NO upon return from `closeDataServer`
 */
@property (readonly, nonatomic) BOOL hasDataServer;

/*!
	\brief
	Wait for a timeout for a connection to appear on the listening socket, the first connection is accepted.
	The data server is automatically closed once a data connection is accepted or the timeout occurs.
 */
- (BOOL)readFirstDataServerConnectionToWriteStream:(NSOutputStream *)outputStream error:(NSError **)errorRef;

/*!
	\brief
	Wait for a timeout for a connection to appear on the listening socket, the first connection is accepted.
	The data server is automatically closed once a data connection is accepted or the timeout occurs.
 */
- (BOOL)writeFirstDataServerConnectionFromReadStream:(NSInputStream *)inputStream error:(NSError **)errorRef;

/*
	PORT support
 */

// Not implemented

@end
