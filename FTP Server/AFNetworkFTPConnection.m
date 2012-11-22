//
//  AFNetworkFTPConnection.m
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkFTPConnection.h"

#import "CoreNetworking/CoreNetworking.h"

@interface AFNetworkFTPConnection () <AFNetworkServerDelegate>
@property (readwrite, retain, nonatomic) AFNetworkServer *dataServer;

@property (retain, nonatomic) NSTimer *dataConnectionTimeout;
@property (readwrite, retain, nonatomic) AFNetworkConnection *dataConnection;
@property (retain, nonatomic) AFNetworkPacket <AFNetworkPacketReading> *dataReadPacket;
@end

@implementation AFNetworkFTPConnection

AFNETWORK_NSSTRING_CONTEXT(_AFNetworkFTPConnectionDataConnectionReadContext);

@dynamic delegate;

@synthesize dataServer=_dataServer;

@synthesize dataConnectionTimeout=_dataConnectionTimeout;
@synthesize dataConnection=_dataConnection;
@synthesize dataReadPacket=_dataReadPacket;

- (void)close {
	[self closeDataServer];
	[self.dataConnectionTimeout invalidate];
	
	[super close];
}

- (AFNetworkSocket *)openDataServerWithAddress:(NSData *)address error:(NSError **)errorRef {
	NSParameterAssert(!self.hasDataServer);
	
	AFNetworkServer *newDataServer = [AFNetworkServer server];
	newDataServer.delegate = self;
	self.dataServer = newDataServer;
	
	return [newDataServer openSocketWithSignature:AFNetworkSocketSignatureInternetTCP address:address error:errorRef];
}

- (void)closeDataServer {
	[self.dataServer close];
	self.dataServer = nil;
	
	[self.dataConnection close];
	self.dataConnection = nil;
}

- (BOOL)hasDataServer {
	return self.dataServer != nil;
}

- (void)readFirstDataServerConnectionToWriteStream:(NSOutputStream *)outputStream {
	NSParameterAssert(self.hasDataServer);
	self.dataReadPacket = [[[AFNetworkPacketReadToWriteStream alloc] initWithTotalBytesToRead:-1 writeStream:outputStream] autorelease];
	
	if (self.dataConnection != nil) {
		[self _didAcceptConnectionOrTimeout];
		return;
	}
	
	self.dataConnectionTimeout = [NSTimer timerWithTimeInterval:60. target:self selector:@selector(_didAcceptConnectionOrTimeout) userInfo:nil repeats:NO];
}

- (BOOL)networkServer:(AFNetworkServer *)server shouldAcceptConnection:(id <AFNetworkConnectionLayer>)connection {
	if (self.dataConnection != nil) {
		return NO;
	}
	
	[server closeListenSockets];
	return YES;
}

- (void)networkServer:(AFNetworkServer *)server didEncapsulateLayer:(id <AFNetworkConnectionLayer>)connection {
	self.dataConnection = (id)connection;
	[self _didAcceptConnectionOrTimeout];
}

- (void)_didAcceptConnectionOrTimeout {
	[self.dataConnectionTimeout invalidate];
	
	if (self.dataConnection == nil) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t establish data connection", nil, [NSBundle bundleWithIdentifier:AFCoreNetworkingBundleIdentifier], @"AFNetworkFTPConnection data connection passive timeout error description"),
		};
		NSError *error = [NSError errorWithDomain:AFCoreNetworkingBundleIdentifier code:AFNetworkErrorUnknown userInfo:errorInfo];
		
		[self.delegate connection:self dataConnectionDidReceiveError:error];
		
		[self closeDataServer];
		return;
	}
	
	AFNetworkPacket <AFNetworkPacketReading> *packet = self.dataReadPacket;
	if (packet == nil) {
		return;
	}
	[self.dataConnection performRead:packet withTimeout:-1 context:&_AFNetworkFTPConnectionDataConnectionReadContext];
}

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didRead:(AFNetworkPacket<AFNetworkPacketReading> *)packet context:(void *)context {
	if (context == &_AFNetworkFTPConnectionDataConnectionReadContext) {
		[self.delegate connectionDidReadDataToWriteStream:self];
	}
	else {
		[super networkLayer:layer didRead:packet context:context];
	}
}

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didReceiveError:(NSError *)error {
	if (layer == self.dataConnection) {
		[self.delegate connection:self dataConnectionDidReceiveError:error];
		return;
	}
	else {
		[super networkLayer:self didReceiveError:error];
	}
}

- (void)networkLayerDidClose:(id <AFNetworkTransportLayer>)layer {
	if (layer == self.dataConnection) {
		
		return;
	}
	else {
		[super networkLayerDidClose:layer];
	}
}

@end
