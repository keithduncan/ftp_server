//
//  AFNetworkFTPMessage.m
//  FTP Server
//
//  Created by Keith Duncan on 09/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import "AFNetworkFTPMessage.h"

NSString *AFNetworkFTPMessageForReplyCode(AFNetworkFTPReplyCode replyCode) {
	switch (replyCode) {
		case AFNetworkFTPReplyCodeAboutToOpenDataConnection:
			return @"About To Open Data Connection";
			
		case AFNetworkFTPReplyCodeCommandOK:
			return @"OK";
		case AFNetworkFTPReplyCodeCommandNotNeeded:
			return @"Command Not Needed";
		case AFNetworkFTPReplyCodeCommandNoFeatures:
			return @"No Features";
		case AFNetworkFTPReplyCodeSystemName:
			break;
		case AFNetworkFTPReplyCodeServiceReadyForNewUser:
			return @"Service Ready For New User";
		case AFNetworkFTPReplyCodeServiceClosingControlConnection:
			return @"Service Closing Control Connection";
		case AFNetworkFTPReplyCodeServiceClosingDataConnection:
			return @"Service Closing Data Connection";
		case AFNetworkFTPReplyCodeEnteringPassiveMode:
			break;
		case AFNetworkFTPReplyCodeUserLoggedIn:
			return @"User Logged In";
		case AFNetworkFTPReplyCodeRequestedFileActionOK:
			return @"Requested File Action OK";
		case AFNetworkFTPReplyCodePathnameCreated:
			break;
			
		case AFNetworkFTPReplyCodeUsernameOkayNeedPassword:
			return @"Username Okay Need Password";
		case AFNetworkFTPReplyCodeUsernameOkayNeedAccount:
			return @"Username Okay Need Account";
			
		case AFNetworkFTPReplyCodeCantOpenDataConnection:
			return @"Can't Open Data Connection";
		case AFNetworkFTPReplyCodeRequestedActionAborted:
			return @"Requested Action Aborted";
			
		case AFNetworkFTPReplyCodeInternalParsingError:
			return @"Internal Parsing Error";
		case AFNetworkFTPReplyCodeParameterSyntaxError:
			return @"Parameter Syntax Error";
		case AFNetworkFTPReplyCodeCommandNotImplemented:
			return @"Command Not Implemented";
		case AFNetworkFTPReplyCodeBadSequenceOfCommands:
			return @"Bad Sequence Of Commands";
		case AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported:
			return @"Command Supported But Parameter Unsupported";
		case AFNetworkFTPReplyCodeNotLoggedIn:
			return @"Not Logged In";
		case AFNetworkFTPReplyCodeRequestedFileActionError:
			return @"Requested File Action Error";
	}
	
	@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"%ld doesn't have a default message", replyCode] userInfo:nil];
}
