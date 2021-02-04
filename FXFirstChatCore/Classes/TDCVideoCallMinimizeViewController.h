//
//  TDCVideoCallMinimizeViewController.h
//  Patient
//
//  Created by ap on 2021/1/28.
//

#import "TUIVideoCallViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface TDCVideoCallMinimizeViewController : TUIVideoCallViewController

- (instancetype)initWithSponsor:(CallUserModel *)sponsor userList:(NSMutableArray<CallUserModel *> *)userList size:(CGSize)size;

-(instancetype)initWithVideoPreView:(UIView*)view;

@end

NS_ASSUME_NONNULL_END
