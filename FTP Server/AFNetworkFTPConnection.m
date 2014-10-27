//
//  AFNetworkFTPConnection.m
//  FTP Server
//
//  Created by Keith Duncan on 20/11/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkFTPConnection.h"

#import "CoreNetworking/CoreNetworking.h"

NSString *const AFNetworkFTPErrorDomain = @"com.thirty-three.corenetworking.ftp";

@interface AFNetworkFTPConnection () <AFNetworkServerDelegate, AFNetworkTransportDelegate>
@property (readwrite, retain, nonatomic) AFNetworkServer *dataServer;

@property (retain, nonatomic) NSTimer *dataConnectionTimeout;
@property (readwrite, retain, nonatomic) AFNetworkTransport *dataConnection;
@property (retain, nonatomic) AFNetworkPacket <AFNetworkPacketReading> *dataReadPacket;
@property (retain, nonatomic) AFNetworkPacket <AFNetworkPacketWriting> *dataWritePacket;
@end

@implementation AFNetworkFTPConnection

AFNETWORK_NSSTRING_CONTEXT(_AFNetworkFTPConnectionDataConnectionReadContext);
AFNETWORK_NSSTRING_CONTEXT(_AFNetworkFTPConnectionDataConnectionWriteContext);

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

- (void)_assertCanOpenDataChannel {
	NSParameterAssert(!self.hasEitherDataServerOrConnection);
}

- (AFNetworkSchedule *)_makeDataSchedule {
	AFNetworkSchedule *schedule = [[[AFNetworkSchedule alloc] init] autorelease];
	[schedule scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
	return schedule;
}

- (void)_makeDataServer {
	[self _assertCanOpenDataChannel];
	
	AFNetworkServer *newDataServer = [AFNetworkServer server];
	newDataServer.delegate = self;
	newDataServer.schedule = [self _makeDataSchedule];
	self.dataServer = newDataServer;
}

- (AFNetworkSocket *)startDataServerWithAddress:(NSData *)address error:(NSError **)errorRef {
	[self _makeDataServer];
	
	return [self.dataServer openSocketWithSignature:AFNetworkSocketSignatureInternetTCP address:address error:errorRef];
}

- (BOOL)connectToDataServerWithAddress:(NSData *)address error:(NSError **)errorRef {
	[self _makeDataServer];
	
	CFHostRef host = (CFHostRef)[NSMakeCollectable(CFHostCreateWithAddress(kCFAllocatorDefault, (CFDataRef)address)) autorelease];
	
	AFNetworkHostSignature transportSignature = {
		.host = host,
		.transport = {
			.type = AFNetworkSocketSignatureInternetTCP,
			.port = af_sockaddr_in_read_port([address bytes]),
		},
	};
	AFNetworkTransport *transport = [[[AFNetworkTransport alloc] initWithTransportSignature:&transportSignature] autorelease];
	
	[self.dataServer addConnection:transport];
	self.dataConnection = transport;
	
	[transport open];
	
	return YES;
}

- (void)closeDataServer {
	[self.dataConnection close];
	self.dataConnection = nil;
	
	[self.dataServer close];
	self.dataServer = nil;
	
	self.dataReadPacket = nil;
	self.dataWritePacket = nil;
}

- (BOOL)hasDataServer {
	return self.dataServer != nil;
}

- (BOOL)hasDataConnection {
	return self.dataConnection != nil;
}

- (BOOL)hasEitherDataServerOrConnection {
	return self.hasDataServer || self.hasDataConnection;
}

- (BOOL)_checkHasDataServerAndCanEnqueuePacket:(NSError **)errorRef {
	if (!self.hasEitherDataServerOrConnection) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFNetworkFTPErrorDomain code:AFNetworkFTPErrorCodeNoDataServer userInfo:nil];
		}
		return NO;
	}
	
	if (self.hasPendingDataConnectionPacket) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFNetworkFTPErrorDomain code:AFNetworkFTPErrorCodeDataAlreadyEnqueued userInfo:nil];
		}
		return NO;
	}
	
	return YES;
}

- (BOOL)readFirstDataServerConnectionToWriteStream:(NSOutputStream *)outputStream error:(NSError **)errorRef {
	if (![self _checkHasDataServerAndCanEnqueuePacket:errorRef]) {
		return NO;
	}
	
	self.dataReadPacket = [[[AFNetworkPacketReadToWriteStream alloc] initWithTotalBytesToRead:-1 writeStream:outputStream] autorelease];
	
	[self _startDataConnectionTimeout];
	return YES;
}

- (BOOL)writeFirstDataServerConnectionFromReadStream:(NSInputStream *)inputStream error:(NSError **)errorRef {
	if (![self _checkHasDataServerAndCanEnqueuePacket:errorRef]) {
		return NO;
	}
	
	self.dataWritePacket = [[[AFNetworkPacketWriteFromReadStream alloc] initWithTotalBytesToWrite:-1 readStream:inputStream] autorelease];
	
	[self _startDataConnectionTimeout];
	return YES;
}

- (BOOL)hasPendingDataConnectionPacket {
	return self.dataReadPacket != nil || self.dataWritePacket != nil;
}

- (void)_assertDoesntHavePendingDataConnectionPacket {
	NSParameterAssert(!self.hasPendingDataConnectionPacket);
}

- (void)_startDataConnectionTimeout {
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

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didReceiveError:(NSError *)error {
	if (layer == self.dataConnection) {
		[self.delegate connection:self dataConnectionDidReceiveError:error];
		[self closeDataServer];
	}
	else {
		[super networkLayer:self didReceiveError:error];
	}
}

- (void)networkLayerDidOpen:(id <AFNetworkTransportLayer>)layer {
	if (layer == self.lowerLayer) {
		return;
	}
	else if (layer == self.dataConnection) {
		[self _didAcceptConnectionOrTimeout];
	}
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
	
	AFNetworkPacket <AFNetworkPacketReading> *readPacket = self.dataReadPacket;
	if (readPacket != nil) {
		[self.dataConnection performRead:readPacket withTimeout:-1 context:&_AFNetworkFTPConnectionDataConnectionReadContext];
	}
	self.dataReadPacket = nil;
	
	AFNetworkPacket <AFNetworkPacketWriting> *writePacket = self.dataWritePacket;
	if (writePacket != nil) {
		[self.dataConnection performWrite:writePacket withTimeout:-1 context:&_AFNetworkFTPConnectionDataConnectionWriteContext];
	}
	self.dataWritePacket = nil;
}

- (void)networkLayer:(id <AFNetworkTransportLayer>)layer didRead:(AFNetworkPacket <AFNetworkPacketReading> *)packet context:(void *)context {
	if (context == &_AFNetworkFTPConnectionDataConnectionReadContext) {
		[self.delegate connectionDidReadDataToWriteStream:self];
	}
	else {
		[super networkLayer:layer didRead:packet context:context];
	}
}

- (void)networkLayer:(id<AFNetworkTransportLayer>)layer didWrite:(AFNetworkPacket <AFNetworkPacketWriting> *)packet context:(void *)context {
	if (context == &_AFNetworkFTPConnectionDataConnectionWriteContext) {
		[self.delegate connectionDidWriteDataFromReadStream:self];
	}
	else {
		[super networkLayer:layer didWrite:packet context:context];
	}
}

- (void)networkLayerDidClose:(id <AFNetworkTransportLayer>)layer {
	if (layer == self.dataConnection) {
		[self closeDataServer];
#warning this needs to be reported so that the control channel can write a reply
	}
	else {
		[super networkLayerDidClose:layer];
	}
}

@end
