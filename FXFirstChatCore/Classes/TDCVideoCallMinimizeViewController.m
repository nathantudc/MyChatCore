//
//  TDCVideoCallMinimizeViewController.m
//  Patient
//
//  Created by ap on 2021/1/28.
//

#import "TDCVideoCallMinimizeViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import "TUIVideoCallUserCell.h"
#import "TUIVideoRenderView.h"
#import "TUICallUtils.h"
#import "THeader.h"
#import "THelper.h"
#import "TUICall.h"
#import "TUICall+TRTC.h"
#import "NSBundle+TUIKIT.h"
#import <Masonry/Masonry.h>

#define kSmallVideoWidth 100.0

@interface TDCVideoCallMinimizeViewController ()

@property(nonatomic,assign) VideoCallState curState;
@property(nonatomic,assign) CGFloat topPadding;
@property(nonatomic,strong) NSMutableArray<CallUserModel *> *avaliableList;
@property(nonatomic,strong) NSMutableArray<CallUserModel *> *userList;
@property(nonatomic,strong) CallUserModel *curSponsor;
@property(nonatomic,assign) BOOL refreshCollectionView;
@property(nonatomic,assign) NSInteger collectionCount;
@property(nonatomic,strong) UIButton *hangup;
@property(nonatomic,strong) UIButton *accept;
@property(nonatomic,strong) UIButton *mute;
@property(nonatomic,strong) UIButton *handsfree;
@property(nonatomic,strong) UILabel *callTimeLabel;
@property(nonatomic,strong) UIView *localPreView;
@property(nonatomic,strong) UIView *sponsorPanel;
@property(nonatomic,strong) NSMutableArray<TUIVideoRenderView *> *renderViews;
@property(nonatomic,strong) dispatch_source_t timer;
@property(nonatomic,assign) UInt32 callingTime;
@property(nonatomic,assign) BOOL playingAlerm; // 播放响铃

@property (nonatomic, strong) UIView *videoContentView;

@end

@implementation TDCVideoCallMinimizeViewController{
    VideoCallState _curState;
    UILabel *_callTimeLabel;
    UIView *_localPreview;
    UIView *_sponsorPanel;
    UICollectionView *_userCollectionView;
    NSInteger _collectionCount;
    NSMutableArray *_userList;
    CGSize customSize;
}



- (instancetype)initWithSponsor:(CallUserModel *)sponsor userList:(NSMutableArray<CallUserModel *> *)userList size:(CGSize)size{
    self = [self initWithSponsor:sponsor userList:userList];
    customSize = size;
    return self;
}

- (instancetype)initWithSponsor:(CallUserModel *)sponsor userList:(NSMutableArray<CallUserModel *> *)userList {
    self = [super init];
    if (self) {
        self.curSponsor = sponsor;
        self.curState = sponsor?VideoCallState_OnInvitee:VideoCallState_Dailing;
        self.renderViews = [NSMutableArray array];
        self.userList = [NSMutableArray array];
        [self resetUserList:^{
            [userList enumerateObjectsUsingBlock:^(CallUserModel * model, NSUInteger idx, BOOL * _Nonnull stop) {
                if (![model.userId isEqualToString:[TUICallUtils loginUser]]) {
                    [self.userList addObject:model];
                }
            }];
        }];
    }
    return self;
}

- (void)resetUserList:(void(^)(void))finished {
    if (self.curSponsor) {
        self.curSponsor.isVideoAvaliable = NO;
        [self.userList addObject:self.curSponsor];
        finished?finished():nil;
        return;
    }
    @weakify(self)
    [TUICallUtils getCallUserModel:[TUICallUtils loginUser] finished:^(CallUserModel * _Nonnull model) {
        @strongify(self)
        model.isEnter = YES;
        model.isVideoAvaliable = YES;
        [self.userList addObject:model];
        finished?finished():nil;
    }];
}

- (void)viewDidLoad {
    [self setupUI];
}

//- (void)viewWillLayoutSubviews{
//    [super viewWillLayoutSubviews];
//    [self setupUI];
//}

- (void)viewWillAppear:(BOOL)animated {
    [self updateCallView:NO];
}

- (void)viewDidAppear:(BOOL)animated {
    [self playAlerm];
}

- (void)disMiss {
    if (self.timer) {
        dispatch_cancel(self.timer);
        self.timer = nil;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
    if (self.dismissBlock) {
        self.dismissBlock();
    }
    [self stopAlerm];
}

- (void)dealloc {
    [[TUICall shareInstance] closeCamara];
}

- (void)enterUser:(CallUserModel *)user {
    if (![user.userId isEqualToString:[TUICallUtils loginUser]]) {
        TUIVideoRenderView *renderView = [[TUIVideoRenderView alloc] init];
        renderView.userModel = user;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
        [renderView addGestureRecognizer:tap];
        [pan requireGestureRecognizerToFail:tap];
        [renderView addGestureRecognizer:pan];
        [self.renderViews addObject:renderView];
        [[TUICall shareInstance] startRemoteView:user.userId view:renderView];
        [self stopAlerm];
    }
    self.curState = VideoCallState_Calling;
    [self updateUser:user animate:YES];
}

- (void)leaveUser:(NSString *)userId {
    [[TUICall shareInstance] stopRemoteView:userId];
    for (TUIVideoRenderView *renderView in self.renderViews) {
        if ([renderView.userModel.userId isEqualToString:userId]) {
            [self.renderViews removeObject:renderView];
            break;
        }
    }
    for (CallUserModel *model in self.userList) {
        if ([model.userId isEqualToString:userId]) {
            BOOL isVideoAvaliable = model.isVideoAvaliable;
            [self.userList removeObject:model];
            [self updateCallView:isVideoAvaliable];
            break;
        }
    }
}

- (void)updateUser:(CallUserModel *)user animate:(BOOL)animate {
    BOOL findUser = NO;
    for (int i = 0; i < self.userList.count; i ++) {
        CallUserModel *model = self.userList[i];
        if ([model.userId isEqualToString:user.userId]) {
            model = user;
            findUser = YES;
            break;
        }
    }
    if (!findUser) {
        [self.userList addObject:user];
    }
    [self updateCallView:animate];
}

- (void)updateCallView:(BOOL)animate {
    [self show1to1CallView];
}

- (void)show1to1CallView {
    self.refreshCollectionView = NO;
    if (self.collectionCount == 2) {
        [self setLocalViewInVCView:CGRectMake(self.view.frame.size.width - kSmallVideoWidth - 18, 20, kSmallVideoWidth, kSmallVideoWidth / 9.0 * 16.0) shouldTap:YES];
        CallUserModel *userFirst;
        for (CallUserModel *model in self.avaliableList) {
            if (![model.userId isEqualToString:[TUICallUtils loginUser]]) {
                userFirst = model;
                break;
            }
        }
        if (userFirst) {
            TUIVideoRenderView *firstRender = [self getRenderView:userFirst.userId];
            if (firstRender) {
                firstRender.userModel = userFirst;
                if (![firstRender.superview isEqual:self.videoContentView]) {
                    [firstRender removeFromSuperview];
                    [self.videoContentView insertSubview:firstRender belowSubview:self.localPreView];
                    [UIView animateWithDuration:0.1 animations:^{
                        firstRender.frame = self.videoContentView.bounds;
                    }];
                } else {
                    firstRender.frame = self.videoContentView.bounds;
                }
            } else {
                NSLog(@"getRenderView error");
            }
        }
    } else { //用户退出只剩下自己（userleave引起的）
        if (self.collectionCount == 1) {
            [self setLocalViewInVCView:self.view.bounds shouldTap:NO];
//            [self setLocalViewInVCView:[UIApplication sharedApplication].keyWindow.bounds shouldTap:NO];
        }
    }
    [self bringControlBtnToFront];
}

- (void)bringControlBtnToFront {
    [self.videoContentView bringSubviewToFront:self.accept];
    [self.videoContentView bringSubviewToFront:self.hangup];
    [self.videoContentView bringSubviewToFront:self.mute];
    [self.videoContentView bringSubviewToFront:self.handsfree];
}

#pragma mark UI
- (void)setupUI {
    self.view.backgroundColor = [UIColor whiteColor];
    if (@available(iOS 11.0, *) ){
        self.topPadding = [UIApplication sharedApplication].keyWindow.safeAreaInsets.top;
    }
    [self.view addSubview:self.videoContentView];
    [_videoContentView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(self.view);
    }];
    [self setupSponsorPanel];
    [self autoSetUIByState];
    [[TUICall shareInstance] openCamera:YES view:self.localPreView];
}

- (void)setupSponsorPanel {
    self.accept.hidden = !self.curSponsor;
    if (!self.curSponsor) return;
    [self.view addSubview:self.sponsorPanel];
    [_sponsorPanel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.mas_equalTo(self.videoContentView).mas_offset(self.topPadding+18);
        make.leading.trailing.mas_equalTo(self.videoContentView);
        make.height.mas_equalTo(60);
    }];
    //发起者头像
    UIImageView *userImage = [[UIImageView alloc] init];
    [userImage sd_setImageWithURL:[NSURL URLWithString:self.curSponsor.avatar] placeholderImage:[UIImage imageNamed:TUIKitResource(@"default_c2c_head")] options:SDWebImageHighPriority];
    [self.sponsorPanel addSubview:userImage];
    [userImage mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.bottom.equalTo(self.sponsorPanel);
        make.width.mas_equalTo(userImage.mas_height);
        make.trailing.mas_equalTo(-16);
    }];
    //发起者名字
    UILabel *userName = [[UILabel alloc] init];
    userName.textAlignment = NSTextAlignmentRight;
    userName.font = [UIFont boldSystemFontOfSize:30];
    userName.textColor = [UIColor whiteColor];
    userName.text = self.curSponsor.name;
    [self.sponsorPanel addSubview:userName];
    [userName mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.mas_equalTo(self.sponsorPanel).multipliedBy(0.5);
        make.trailing.mas_equalTo(userImage.mas_leading).mas_offset(-6);
    }];
    //提醒文字
    UILabel *invite = [[UILabel alloc] init];
    invite.textAlignment = NSTextAlignmentRight;
    invite.font = [UIFont systemFontOfSize:13];
    invite.textColor = [UIColor whiteColor];
    invite.text = TUILocalizableString(TUIKitCallInviteYouVideoCall); // @"邀请你视频通话";
    [self.sponsorPanel addSubview:invite];
    [invite mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.mas_equalTo(self.sponsorPanel).multipliedBy(1.5);
        make.trailing.mas_equalTo(userName);
    }];
}

- (void)autoSetUIByState {
    if (self.curSponsor) self.sponsorPanel.hidden = (self.curState == VideoCallState_Calling);
    switch (self.curState) {
        case VideoCallState_Dailing:{
            [self.hangup mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX);
                make.size.mas_equalTo(CGSizeMake(50, 50));
                make.bottom.mas_equalTo(self.videoContentView).mas_offset(-32);
            }];
        }
            break;
        case VideoCallState_OnInvitee:{
            [self.hangup mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX).mas_offset(-80);
                make.size.mas_equalTo(CGSizeMake(50, 50));
                make.bottom.mas_equalTo(self.videoContentView).mas_offset(-32);
            }];
            [self.accept mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX).mas_offset(80);
                make.size.mas_equalTo(self.hangup);
                make.bottom.mas_equalTo(self.hangup);
            }];
        }
            break;
        case VideoCallState_Calling:
        {
            [self.hangup mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX);
                make.size.mas_equalTo(CGSizeMake(50, 50));
                make.bottom.mas_equalTo(self.videoContentView).mas_offset(-32);
            }];
            [self.mute mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX).mas_offset(-120);
                make.size.mas_equalTo(self.hangup);
                make.bottom.mas_equalTo(self.hangup);
            }];
            [self.handsfree mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX).mas_offset(120);
                make.size.mas_equalTo(self.hangup);
                make.bottom.mas_equalTo(self.hangup);
            }];
            [self.callTimeLabel mas_makeConstraints:^(MASConstraintMaker *make) {
                make.centerX.mas_equalTo(self.videoContentView.mas_centerX);
                make.bottom.mas_equalTo(self.hangup.mas_top).mas_offset(-12);
            }];
            self.mute.hidden = NO;
            self.handsfree.hidden = NO;
            self.callTimeLabel.hidden = NO;
            self.mute.alpha = 0.0;
            self.handsfree.alpha = 0.0;
            [self startCallTiming];
        }
            break;
        default:
            break;
    }
    [UIView animateWithDuration:0.25 animations:^{
        [self.videoContentView layoutIfNeeded];
        if (self.curState == VideoCallState_Calling) {
            self.mute.alpha = 1.0;
            self.handsfree.alpha = 1.0;
        }
    }];
}


- (void)startCallTiming {
    if (self.timer) {
        dispatch_cancel(self.timer);
        self.timer = nil;
    }
    self.callingTime = 0;
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(0, 0));
    dispatch_source_set_timer(self.timer, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(self.timer, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.callTimeLabel.text = [NSString stringWithFormat:@"%02d:%02d",(int)self.callingTime / 60, (int)self.callingTime % 60];
            self.callingTime += 1;
        });
    });
    dispatch_resume(self.timer);
}


//- (void)setLocalViewInVCView:(CGRect)frame shouldTap:(BOOL)shouldTap {
//    if (CGRectEqualToRect(self.localPreView.frame, frame)) return;
//    self.localPreView.userInteractionEnabled = YES;
//    [self.localPreView setUserInteractionEnabled:shouldTap];
//    [self.localPreView.subviews.firstObject setUserInteractionEnabled:!shouldTap];
//    [UIView animateWithDuration:0.25 animations:^{
//        [self.localPreView mas_remakeConstraints:^(MASConstraintMaker *make) {
//            make.leading.mas_equalTo(frame.origin.x);
//            make.top.mas_equalTo(frame.origin.y);
//            make.size.mas_equalTo(frame.size);
//        }];
//        [self.localPreView layoutIfNeeded];
//    }];
//}

- (void)setLocalViewInVCView:(CGRect)frame shouldTap:(BOOL)shouldTap {
    if (CGRectEqualToRect(self.localPreView.frame, frame)) {
        return;
    }
    [self.localPreView setUserInteractionEnabled:shouldTap];
    [self.localPreView.subviews.firstObject setUserInteractionEnabled:!shouldTap];
    [UIView animateWithDuration:0.3 animations:^{
        self.localPreView.frame = frame;
    }];
}

- (UIButton *)hangup {
    if (!_hangup.superview) {
        _hangup = [UIButton buttonWithType:UIButtonTypeCustom];
        [_hangup setImage:[UIImage imageNamed:TUIKitResource(@"ic_hangup")] forState:UIControlStateNormal];
        [_hangup addTarget:self action:@selector(hangupClick) forControlEvents:UIControlEventTouchUpInside];
        [self.videoContentView addSubview:_hangup];
    }
    return _hangup;
}

- (UIButton *)accept {
    if (!_accept.superview) {
        _accept = [UIButton buttonWithType:UIButtonTypeCustom];
        [_accept setImage:[UIImage imageNamed:TUIKitResource(@"ic_dialing")] forState:UIControlStateNormal];
        [_accept addTarget:self action:@selector(acceptClick) forControlEvents:UIControlEventTouchUpInside];
        _accept.hidden = (self.curSponsor == nil);
        [self.videoContentView addSubview:_accept];
    }
    return _accept;
}

- (UIButton *)mute {
    if (!_mute.superview) {
        _mute = [UIButton buttonWithType:UIButtonTypeCustom];
        [_mute setImage:[UIImage imageNamed:TUIKitResource(@"ic_mute")] forState:UIControlStateNormal];
        [_mute addTarget:self action:@selector(muteClick) forControlEvents:UIControlEventTouchUpInside];
        _mute.hidden = YES;
        [self.videoContentView addSubview:_mute];
    }
    return _mute;
}

- (UIButton *)handsfree {
    if (!_handsfree.superview) {
        _handsfree = [UIButton buttonWithType:UIButtonTypeCustom];
        [_handsfree setImage:[UIImage imageNamed:TUIKitResource(@"ic_handsfree_on")] forState:UIControlStateNormal];
        [_handsfree addTarget:self action:@selector(handsfreeClick) forControlEvents:UIControlEventTouchUpInside];
        _handsfree.hidden = YES;
        [self.videoContentView addSubview:_handsfree];
    }
    return _handsfree;
}

- (UILabel *)callTimeLabel {
    if (!_callTimeLabel.superview) {
        _callTimeLabel = [[UILabel alloc] init];
        _callTimeLabel.backgroundColor = [UIColor clearColor];
        _callTimeLabel.text = @"00:00";
        _callTimeLabel.textColor = [UIColor whiteColor];
        _callTimeLabel.textAlignment = NSTextAlignmentCenter;
        _callTimeLabel.hidden = YES;
        [self.videoContentView addSubview:_callTimeLabel];
    }
    return _callTimeLabel;
}

- (UIView *)sponsorPanel {
    if (!_sponsorPanel) {
        _sponsorPanel = [[UIView alloc] init];
        _sponsorPanel.backgroundColor = [UIColor clearColor];
    }
    return _sponsorPanel;
}

- (UIView *)localPreView {
    if (!_localPreView) {
//        CGRect frame = [UIApplication sharedApplication].keyWindow.bounds;
        CGRect frame = CGRectMake(0, 0, customSize.width, customSize.height);
        _localPreView = [[UIView alloc] initWithFrame:frame];
//        _localPreView = [[UIView alloc] init];
        _localPreView.userInteractionEnabled = NO;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
        [pan requireGestureRecognizerToFail:tap];
        [_localPreView addGestureRecognizer:tap];
        [_localPreView addGestureRecognizer:pan];
        [self.videoContentView addSubview:_localPreView];
        [_localPreview mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.mas_equalTo(self.videoContentView);
        }];
    }
    return _localPreView;
}

-(UIView*)videoContentView{
    if (!_videoContentView) {
        _videoContentView = [UIView new];
    }
    return _videoContentView;
}

#pragma mark - 响铃🔔
// 播放铃声
- (void)playAlerm {
    self.playingAlerm = YES;
    [self loopPlayAlert];
}

// 结束播放铃声
- (void)stopAlerm {
    self.playingAlerm = NO;
}

// 循环播放声音
- (void)loopPlayAlert {
    if (!self.playingAlerm)  return;
    @weakify(self)
    AudioServicesPlaySystemSoundWithCompletion(1012, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @strongify(self)
            [self loopPlayAlert];
        });
    });
}

#pragma mark click

- (void)hangupClick {
    [[TUICall shareInstance] hangup];
    [self disMiss];
}

- (void)acceptClick {
    [[TUICall shareInstance] accept];
    @weakify(self)
    [TUICallUtils getCallUserModel:[TUICallUtils loginUser] finished:^(CallUserModel * _Nonnull model) {
        @strongify(self)
        model.isEnter = YES;
        model.isVideoAvaliable = YES;
        [self enterUser:model];
        self.curState = VideoCallState_Calling;
        self.accept.hidden = YES;
    }];
}

- (void)muteClick {
    BOOL micMute = ![TUICall shareInstance].micMute;
    [[TUICall shareInstance] mute:micMute];
    [self.mute setImage:[TUICall shareInstance].isMicMute ? [UIImage imageNamed:TUIKitResource(@"ic_mute_on")] : [UIImage imageNamed:TUIKitResource(@"ic_mute")]  forState:UIControlStateNormal];
    if (micMute) {
        [THelper makeToast:TUILocalizableString(TUIKitCallTurningOnMute) duration:1 position:CGPointMake(self.hangup.mm_centerX, self.hangup.mm_minY - 60)];
    } else {
        [THelper makeToast:TUILocalizableString(TUIKitCallTurningOffMute) duration:1 position:CGPointMake(self.hangup.mm_centerX, self.hangup.mm_minY - 60)];
    }
}

- (void)handsfreeClick {
    BOOL handsFreeOn = ![TUICall shareInstance].handsFreeOn;
    [[TUICall shareInstance] handsFree:handsFreeOn];
    [self.handsfree setImage:[TUICall shareInstance].isHandsFreeOn ? [UIImage imageNamed:TUIKitResource(@"ic_handsfree_on")] : [UIImage imageNamed:TUIKitResource(@"ic_handsfree")]  forState:UIControlStateNormal];
    if (handsFreeOn) {
        [THelper makeToast:TUILocalizableString(TUIKitCallUsingSpeaker) duration:1 position:CGPointMake(self.hangup.mm_centerX, self.hangup.mm_minY - 60)];
    } else {
        [THelper makeToast:TUILocalizableString(TUIKitCallUsingHeadphone) duration:1 position:CGPointMake(self.hangup.mm_centerX, self.hangup.mm_minY - 60)];
    }
}

- (void)handleTapGesture:(UIPanGestureRecognizer *)tap {
    if (self.collectionCount != 2) return;
    if ([tap.view isEqual:self.localPreView]) {
        if (self.localPreView.frame.size.width == kSmallVideoWidth) {
            CallUserModel *userFirst;
            for (CallUserModel *model in self.avaliableList) {
                if (![model.userId isEqualToString:[TUICallUtils loginUser]]) {
                    userFirst = model;
                    break;
                }
            }
            if (userFirst) {
                TUIVideoRenderView *firstRender = [self getRenderView:userFirst.userId];
                [firstRender removeFromSuperview];
                [self.videoContentView insertSubview:firstRender aboveSubview:self.localPreView];
                [UIView animateWithDuration:0.3 animations:^{
                    self.localPreView.frame = self.videoContentView.frame;
                    firstRender.frame = CGRectMake(self.videoContentView.frame.size.width - kSmallVideoWidth - 18, 20, kSmallVideoWidth, kSmallVideoWidth / 9.0 * 16.0);
                }];
            }
        }
        return;
    }
    UIView *smallView = tap.view;
    if (smallView.frame.size.width == kSmallVideoWidth) {
        [smallView removeFromSuperview];
        [self.videoContentView insertSubview:smallView belowSubview:self.localPreView];
        [UIView animateWithDuration:0.3 animations:^{
            smallView.frame = self.videoContentView.frame;
            self.localPreView.frame = CGRectMake(self.videoContentView.frame.size.width - kSmallVideoWidth - 18, 20, kSmallVideoWidth, kSmallVideoWidth / 9.0 * 16.0);
        }];
    }
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)pan {
    UIView *smallView = pan.view;
    if (smallView) {
        if (pan.view.frame.size.width == kSmallVideoWidth) {
            if (pan.state == UIGestureRecognizerStateBegan) {
                
            } else if (pan.state == UIGestureRecognizerStateChanged) {
                CGPoint translation = [pan translationInView:self.view];
                CGFloat newCenterX = translation.x + (smallView.center.x);
                CGFloat newCenterY = translation.y + (smallView.center.y);
                if (( newCenterX < (smallView.bounds.size.width) / 2) ||
                    ( newCenterX > self.videoContentView.bounds.size.width - (smallView.bounds.size.width) / 2))  {
                    return;
                }
                if (( newCenterY < (smallView.bounds.size.height) / 2) ||
                    (newCenterY > self.videoContentView.bounds.size.height - (smallView.bounds.size.height) / 2))  {
                    return;
                }
                [UIView animateWithDuration:0.1 animations:^{
                    smallView.center = CGPointMake(newCenterX, newCenterY);
                }];
                [pan setTranslation:CGPointZero inView:self.view];
            } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
                
            }
        }
    }
}

#pragma mark data
- (NSMutableArray <CallUserModel *> *)avaliableList {
    NSMutableArray *avaliableList = [NSMutableArray array];
    for (CallUserModel *model in self.userList) {
        if (model.isEnter) {
            [avaliableList addObject:model];
        }
    }
    return avaliableList;
}

- (void)setCurState:(VideoCallState)curState {
    if (_curState != curState) {
        _curState = curState;
        [self autoSetUIByState];
    }
}

- (VideoCallState)curState {
    return _curState;
}

- (NSInteger)collectionCount {
    _collectionCount = (self.avaliableList.count <= 4 ? self.avaliableList.count : 9);
    if (self.curState == VideoCallState_OnInvitee || self.curState == VideoCallState_Dailing) {
        _collectionCount = 0;
    }
    return _collectionCount;
}

- (CallUserModel *)getUserById:(NSString *)userID {
    for (CallUserModel *user in self.userList) {
        if ([user.userId isEqualToString:userID]) {
            return user;
        }
    }
    return nil;
}

- (TUIVideoRenderView *)getRenderView:(NSString *)userID {
    for (TUIVideoRenderView *renderView in self.renderViews) {
        if ([renderView.userModel.userId isEqualToString:userID]) {
            return renderView;
        }
    }
    return nil;
}

@end
