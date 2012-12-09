//
//  AFNetworkTelnetConnection.m
//  FTP Server
//
//  Created by Keith Duncan on 06/08/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkTelnetConnection.h"

@implementation AFNetworkTelnetConnection

static NSString *_AFNetworkTelnetConnectionWriteReplyContext = @"_AFNetworkTelnetConnectionWriteReplyContext";
static NSString *_AFNetworkTelnetConnectionReadLineContext = @"_AFNetworkTelnetConnectionReadLineContext";

@dynamic delegate;

@synthesize defaultMessageFunction=_defaultMessageFunction;

- (void)_writeReply:(NSUInteger)replyCode separator:(NSString *)separator suffix:(NSString *)suffix readLine:(void *)readLine {
	NSParameterAssert([separator canBeConvertedToEncoding:NSASCIIStringEncoding]);
	NSParameterAssert([suffix canBeConvertedToEncoding:NSASCIIStringEncoding]);
	NSStringEncoding wireEncoding = NSASCIIStringEncoding;
	
	NSMutableData *reply = [NSMutableData data];
	
	NSString *replyCodeString = [NSString stringWithFormat:@"%lu", (unsigned long)replyCode];
	[reply appendData:[replyCodeString dataUsingEncoding:wireEncoding]];
	
	[reply appendData:[separator dataUsingEncoding:wireEncoding]];
	
	if (suffix != nil) {
		[reply appendData:[suffix dataUsingEncoding:wireEncoding]];
	}
	
	[reply appendData:[NSData dataWithBytes:"\r\n" length:2]];
	
	AFNetworkPacketWrite *packet = [[[AFNetworkPacketWrite alloc] initWithData:reply] autorelease];
	
	[self performWrite:packet withTimeout:0 context:&_AFNetworkTelnetConnectionWriteReplyContext];
	
	if (readLine != NULL) {
		[self readLineWithContext:readLine];
	}
}

- (void)writeReply:(NSUInteger)replyCode mark:(NSString *)mark {
	if (mark == nil && self.defaultMessageFunction != NULL) {
		mark = self.defaultMessageFunction(replyCode);
	}
	[self _writeReply:replyCode separator:@"-" suffix:mark readLine:NULL];
}

- (void)writeReply:(NSUInteger)replyCode message:(NSString *)message readLine:(void *)readLine {
	if (message == nil && self.defaultMessageFunction != NULL) {
		message = self.defaultMessageFunction(replyCode);
	}
	[self _writeReply:replyCode separator:@" " suffix:message readLine:readLine];
}

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didWrite:(id <AFNetworkPacketWriting>)packet context:(void *)context {
	if (context == &_AFNetworkTelnetConnectionWriteReplyContext) {
		[self.delegate connection:self didWriteReply:[(AFNetworkPacketWrite *)packet buffer] context:context];
	}
	else {
		[super networkLayer:layer didWrite:packet context:context];
	}
}

- (void)readLineWithContext:(void *)context {
#warning support multiline messages from the client
	
	NSData *newlineTerminator = [NSData dataWithBytes:"\r\n" length:2];
	AFNetworkPacketRead *readPacket = [[[AFNetworkPacketRead alloc] initWithTerminator:newlineTerminator] autorelease];
	
	NSValue *userContext = [NSValue valueWithPointer:context];
	[[readPacket userInfo] setObject:userContext forKey:@"context"];
	
	[self performRead:readPacket withTimeout:0 context:&_AFNetworkTelnetConnectionReadLineContext];
}

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didRead:(id <AFNetworkPacketReading>)packet context:(void *)context {
	if (context == &_AFNetworkTelnetConnectionReadLineContext) {
		NSData *lineData = [(AFNetworkPacketRead *)packet buffer];
		lineData = [lineData subdataWithRange:NSMakeRange(0, [lineData length] - [(NSData *)[(AFNetworkPacketRead *)packet terminator] length])];
		
		NSString *line = [[[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding] autorelease];
		
		NSValue *userContext = [[(AFNetworkPacket *)packet userInfo] objectForKey:@"context"];
		
		[self.delegate connection:self didReadLine:line context:[userContext pointerValue]];
	}
	else {
		[super networkLayer:layer didRead:packet context:context];
	}
}

@end
