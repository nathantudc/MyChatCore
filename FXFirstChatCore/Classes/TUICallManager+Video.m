//
//  TUICallManager+Video.m
//  Patient
//
//  Created by ap on 2021/1/27.
//

#import "TUICallManager+Video.h"
#import "TUIVideoCallViewController.h"
#import "TUIAudioCallViewController.h"
#import "TDCVideoCallMinimizeViewController.h"

@implementation TUICallManager (Video)

- (void)showCallVC:(NSMutableArray<CallUserModel *> *)invitedList sponsor:(CallUserModel *)sponsor {
    CallType type = (CallType)[[self valueForKey:@"type"] integerValue];
    if (type == CallType_Video) {
        CGRect bounds = [UIScreen mainScreen].bounds;
//        TDCVideoCallMinimizeViewController *vc = [[TDCVideoCallMinimizeViewController alloc] initWithSponsor:sponsor userList:invitedList];
        TDCVideoCallMinimizeViewController *vc = [[TDCVideoCallMinimizeViewController alloc] initWithSponsor:sponsor userList:invitedList size:bounds.size];
        [self setValue:vc forKey:@"callVC"];
        TDCVideoCallMinimizeViewController *videoVC = (TDCVideoCallMinimizeViewController *)vc;
        videoVC.dismissBlock = ^{
            TUIVideoCallViewController *vc = [self valueForKey:@"callVC"];
            [vc.view removeFromSuperview];
            vc = nil;
        };
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        vc.view.frame = bounds;
        [window addSubview:vc.view];
//        [videoVC setModalPresentationStyle:UIModalPresentationFullScreen];
//        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:videoVC animated:YES completion:nil];
        return;
    }
        TUIAudioCallViewController *vc  = [[TUIAudioCallViewController alloc] initWithSponsor:sponsor userList:invitedList];
        TUIAudioCallViewController *audioVC = (TUIAudioCallViewController *)vc;
        [self setValue:vc forKey:@"callVC"];
        audioVC.dismissBlock = ^{
            TUIAudioCallViewController *vc = [self valueForKey:@"callVC"];
            vc = nil;
        };
        [audioVC setModalPresentationStyle:UIModalPresentationFullScreen];
        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:audioVC animated:YES completion:nil];
}

@end
