//
//  TDCChatCoreConfig.h
//  ChatCore
//
//  Created by ap on 2021/2/2.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TDCChatCoreConfig : NSObject

/// 初始化
/// @param appid 腾讯IM appid
/// @param secretKey 腾讯 secretKey
-(instancetype)initWithAppid:(NSString*)appid secretKey:(NSString*)secretKey NS_DESIGNATED_INITIALIZER;

-(instancetype)init NS_UNAVAILABLE;

+(instancetype)new NS_UNAVAILABLE;

+(void)initialize NS_UNAVAILABLE;

@end

@interface TDCChatCore : NSObject

+(void)initTencentIMSDKWithConfig:(TDCChatCoreConfig *)config;

+(void)loginWithUserID:(NSString*)userid handle:(void(^)(BOOL success))handle;

-(instancetype)init NS_UNAVAILABLE;

+(instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
