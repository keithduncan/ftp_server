//
//  AFNetworkTelnetConnection.h
//  FTP Server
//
//  Created by Keith Duncan on 06/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "CoreNetworking/CoreNetworking.h"

@class AFNetworkTelnetConnection;

@protocol AFTelnetConnectionDelegate <AFNetworkConnectionDelegate>

- (void)connection:(AFNetworkTelnetConnection *)connection didWriteReply:(NSData *)reply context:(void *)context;

- (void)connection:(AFNetworkTelnetConnection *)connection didReadLine:(NSString *)line context:(void *)context;

@end

/*!
	\brief
	Messages are terminated with \r\n
 */
@interface AFNetworkTelnetConnection : AFNetworkConnection

@property (assign, nonatomic) id <AFTelnetConnectionDelegate> delegate;

@property (assign, nonatomic) NSString * (*defaultMessageFunction)(NSUInteger);

- (void)writeReply:(NSUInteger)replyCode mark:(NSString *)mark;
- (void)writeReply:(NSUInteger)replyCode message:(NSString *)message readLine:(void *)readLine;

- (void)readLineWithContext:(void *)context;

@end
