//
//  TDCChatCoreConfig.m
//  ChatCore
//
//  Created by ap on 2021/2/2.
//

#import "TDCChatCore.h"
#import <TXIMSDK_TUIKit_iOS/TUIKit.h>
#import <CommonCrypto/CommonCrypto.h>
#import <zlib.h>

static const int EXPIRETIME = 604800;
//static const int SDKBusiId = 604800;

@interface TDCChatCoreConfig()

@property (nonatomic, copy) NSString *appid;
@property (nonatomic, copy) NSString *secretKey;

@end

@implementation TDCChatCoreConfig

-(instancetype)initWithAppid:(NSString*)appid secretKey:(NSString*)secretKey{
    self = [super init];
    if (self) {
        _appid = appid;
        _secretKey = secretKey;
    }
    return self;
}

@end

@implementation TDCChatCore 

static TDCChatCoreConfig *ChatCoreConfig = nil;

+(void)initTencentIMSDKWithConfig:(TDCChatCoreConfig *)config{
    NSAssert(config,@"config must not be nil");
    ChatCoreConfig = config;
    NSInteger appid = [config.appid integerValue];
    [[TUIKit sharedInstance] setupWithAppId:(UInt32)appid logLevel:V2TIM_LOG_NONE];
}

+(void)loginWithUserID:(NSString*)userid handle:(void(^)(BOOL success))handle{
    NSAssert(ChatCoreConfig,@"you must call initTencentIMSDKWithConfig first");
    NSString *userSig = [self genTestUserSig:userid];
    [[TUIKit sharedInstance] login:userid userSig:userSig succ:^{
        handle?handle(YES):nil;
    } fail:^(int code, NSString *msg) {
        NSLog(@"login tencent error code = %@, msg = %@",@(code),msg);
        handle?handle(NO):nil;
    }];
}

#pragma mark - tool function

+(NSString *)genTestUserSig:(NSString *)identifier{
    CFTimeInterval current = CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970;
    long TLSTime = floor(current);
    NSMutableDictionary *obj = [@{@"TLS.ver": @"2.0",
                                  @"TLS.identifier": identifier,
                                  @"TLS.sdkappid":ChatCoreConfig.appid,
                                  @"TLS.expire": @(EXPIRETIME),
                                  @"TLS.time": @(TLSTime)} mutableCopy];
    NSMutableString *stringToSign = [[NSMutableString alloc] init];
    NSArray *keyOrder = @[@"TLS.identifier",
                          @"TLS.sdkappid",
                          @"TLS.time",
                          @"TLS.expire"];
    for (NSString *key in keyOrder) {
        [stringToSign appendFormat:@"%@:%@\n", key, obj[key]];
    }
    NSString *sig = [self hmac:stringToSign];
    obj[@"TLS.sig"] = sig;
    NSError *error = nil;
    NSData *jsonToZipData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
    if (error) {
        NSLog(@"[Error] json serialization failed: %@", error);
        return @"";
    }
    const Bytef* zipsrc = (const Bytef*)[jsonToZipData bytes];
    uLongf srcLen = jsonToZipData.length;
    uLong upperBound = compressBound(srcLen);
    Bytef *dest = (Bytef*)malloc(upperBound);
    uLongf destLen = upperBound;
    int ret = compress2(dest, &destLen, (const Bytef*)zipsrc, srcLen, Z_BEST_SPEED);
    if (ret != Z_OK) {
        free(dest);
        return @"";
    }
    NSString *result = [self base64URL: [NSData dataWithBytesNoCopy:dest length:destLen]];
    return result;
}

+ (NSString *)hmac:(NSString *)plainText{
    const char *cKey  = [ChatCoreConfig.secretKey cStringUsingEncoding:NSASCIIStringEncoding];
    const char *cData = [plainText cStringUsingEncoding:NSASCIIStringEncoding];
    unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
    NSData *HMACData = [[NSData alloc] initWithBytes:cHMAC length:sizeof(cHMAC)];
    return [HMACData base64EncodedStringWithOptions:0];
}

+ (NSString *)base64URL:(NSData *)data{
    NSString *result = [data base64EncodedStringWithOptions:0];
    NSMutableString *final = [[NSMutableString alloc] init];
    const char *cString = [result cStringUsingEncoding:NSUTF8StringEncoding];
    for (int i = 0; i < result.length; ++ i) {
        char x = cString[i];
        switch(x){
            case '+':
                [final appendString:@"*"];
                break;
            case '/':
                [final appendString:@"-"];
                break;
            case '=':
                [final appendString:@"_"];
                break;
            default:
                [final appendFormat:@"%c", x];
                break;
        }
    }
    return final;
}

@end
