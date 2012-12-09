//
//  AFNetworkFTPMessage.h
//  FTP Server
//
//  Created by Keith Duncan on 09/12/2012.
//  Copyright (c) 2012 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

typedef AFNETWORK_ENUM(NSUInteger, AFNetworkFTPReplyCode) {
	AFNetworkFTPReplyCodeAboutToOpenDataConnection					= 150,
	
	AFNetworkFTPReplyCodeCommandOK									= 200,
	AFNetworkFTPReplyCodeCommandNotNeeded							= 202,
	AFNetworkFTPReplyCodeCommandNoFeatures							= 211,
	AFNetworkFTPReplyCodeSystemName									= 215,
	AFNetworkFTPReplyCodeServiceReadyForNewUser						= 220,
	AFNetworkFTPReplyCodeServiceClosingControlConnection			= 221,
	AFNetworkFTPReplyCodeServiceClosingDataConnection				= 226,
	AFNetworkFTPReplyCodeEnteringPassiveMode						= 227,
	AFNetworkFTPReplyCodeUserLoggedIn								= 230,
	AFNetworkFTPReplyCodeRequestedFileActionOK						= 250,
	AFNetworkFTPReplyCodePathnameCreated							= 257,
	
	AFNetworkFTPReplyCodeUsernameOkayNeedPassword					= 331,
	AFNetworkFTPReplyCodeUsernameOkayNeedAccount					= 332,
	
	AFNetworkFTPReplyCodeCantOpenDataConnection						= 425,
	AFNetworkFTPReplyCodeRequestedActionAborted						= 451,
	
	AFNetworkFTPReplyCodeInternalParsingError						= 500,
	AFNetworkFTPReplyCodeParameterSyntaxError						= 501,
	AFNetworkFTPReplyCodeCommandNotImplemented						= 502,
	AFNetworkFTPReplyCodeBadSequenceOfCommands						= 503,
	AFNetworkFTPReplyCodeCommandSupportedButParameterUnsupported	= 504,
	AFNetworkFTPReplyCodeNotLoggedIn								= 530,
	AFNetworkFTPReplyCodeRequestedFileActionError					= 550,
};

AFNETWORK_EXTERN NSString *AFNetworkFTPMessageForReplyCode(AFNetworkFTPReplyCode replyCode);
