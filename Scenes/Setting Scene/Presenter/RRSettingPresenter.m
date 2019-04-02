//
//  RRSettingPresenter.m
//  rework-reader
//
//  Created by 张超 on 2019/1/28.
//  Copyright © 2019 orzer. All rights reserved.
//

#import "RRSettingPresenter.h"
#import "RRModelItem.h"
#import "RPSettingInputer.h"
@import SafariServices;
#import "RRFeedLoader.h"
@import ui_base;
#import "MVPViewLoadProtocol.h"
#import "RRGetWebIconOperation.h"
@import UserNotifications;
#import "OPMLDocument.h"
@import Classy;
#import "RRDataBackuper.h"
#import "ApplePurchaseDelegate.h"
#import "AppleAPIHelper.h"
#import "PWToastView.h"
@import YYKit;
#import "RPDataManager.h"
#import "RRCoreDataModel.h"

@interface RRSettingPresenter () <UIDocumentPickerDelegate,MVPPresenterProtocol_private,SKStoreProductViewControllerDelegate>
{
    
}
@property (nonatomic, strong) RRModelItem* item;
@property (nonatomic, strong) RPSettingInputer* inputer;
@property (nonatomic, assign) BOOL feeding;
@property (nonatomic, weak) RRSetting* notiSetting;
@property (nonatomic, weak) RRSetting* badgeSetting;
@property (nonatomic, weak) RRSetting* enterUnreadSetting;
@property (nonatomic, weak) RRSetting* iCloudSetting;
@property (nonatomic, weak) RRSetting* toolBackSetting;
@property (nonatomic, weak) FMFeedParserOperation* currentOperation;
@property (nonatomic, strong) NSString* settingFileName;
@property (nonatomic, strong) RRDataBackuper* backuper;

@property (nonatomic, strong) RRSetting* donateSetting;
@property (nonatomic, strong) void (^ purchasedBlock)(SKPaymentTransaction* t);

@property (nonatomic, assign) BOOL exporting;
@end

@implementation RRSettingPresenter

- (RPSettingInputer *)inputer
{
    if (!_inputer) {
        _inputer = [[RPSettingInputer alloc] init];
    }
    return _inputer;
}

- (RRModelItem *)item
{
    if (!_item) {
        NSError *error;
        NSError *error2;
        NSURL* url = [[NSBundle mainBundle] URLForResource:self.settingFileName withExtension:@"json"];
        NSString* json = [[NSString alloc] initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            DDLogError(@"%@",error);
        }
        _item = [RRModelItem fromJSON:json encoding:NSUTF8StringEncoding error:&error2];
        if (error2) {
            DDLogError(@"%@",error2);
        }
    }
    return _item;
}

- (void)mvp_initFromModel:(MVPInitModel *)model
{
    NSLog(@"paied %@",@([self isPaied]));
    
    
    NSString* setting = [model.queryProperties valueForKey:@"setting"];
    if (setting) {
        self.settingFileName = setting;
    }
    else {
        self.settingFileName = @"ModelTypeSetting";
        [[ApplePurchaseDelegate sharedOne].products enumerateObjectsUsingBlock:^(SKProduct * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSLog(@"%@",obj);
//            NSString* title = obj.localizedTitle?obj.localizedTitle:NSLocalizedString(@"赞助开发者", nil);
//            NSString* cost = [NSNumberFormatter localizedStringFromNumber:obj.price numberStyle:NSNumberFormatterCurrencyStyle];
            NSNumberFormatter* f = [[NSNumberFormatter alloc] init];
            [f setLocale:obj.priceLocale];
            [f setNumberStyle:NSNumberFormatterCurrencyPluralStyle];
            //        [f setCurrencyCode:obj.priceLocale.currencyCode];
//            NSLog(@"%@",[f stringFromNumber:obj.price]);
            
            RRSetting* setting = [[RRSetting alloc] init];
            setting.title = obj.localizedTitle;
            if([self isPaied])
            {
                setting.value = @"已赞助";
            }
            else {
                setting.value = [f stringFromNumber:obj.price];
            }
            setting.action = @"donate";
            setting.type = @(RRSettingTypeBase);
            self.donateSetting = setting;
            [self.inputer mvp_addModel:setting];
        }];
    }
    NSString* title = [model.queryProperties valueForKey:@"title"];
    if (title) {
        self.title = title;
    }
    else {
        self.title = @"更多内容";
    }
    __weak typeof(self) weakSelf = self;
    [[self.item setting] enumerateObjectsUsingBlock:^(RRSetting * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj.type integerValue] == RRSettingTypeSwitch) {
//            if ([[obj switchkey] isEqualToString:@"kBackgroundFetchNoti"]) {
//                weakSelf.notiSetting = obj;
//            }
//            else if([[obj switchkey] isEqualToString:@"kBackgroundFetchNotiBadge"])
//            {
//                weakSelf.badgeSetting = obj;
//            }
//            else if([[obj switchkey] isEqualToString:@"kEnterUnread"])
//            {
//                weakSelf.enterUnreadSetting = obj;
//            }
            [weakSelf setValue:obj forKey:obj.select];
            if ([obj switchkey]) {
                obj.switchValue = [[NSUserDefaults standardUserDefaults] valueForKey:obj.switchkey];
            }
        }
        
        if ([[obj title] isEqualToString:@"版本"]) {
            [obj setValue:[NSString stringWithFormat:@"%@ (build %@)",[UIApplication sharedApplication].version(),[UIApplication sharedApplication].buildVersion()]];
        }
        [weakSelf.inputer mvp_addModel:obj];
    }];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
       
    }
    return self;
}


- (id)mvp_inputerWithOutput:(id<MVPOutputProtocol>)output
{
    return self.inputer;
}

- (void)mvp_action_selectItemAtIndexPath:(NSIndexPath *)path
{
    RRSetting* s = [self.inputer mvp_modelAtIndexPath:path];
    if ([s.type integerValue] == RRSettingTypeOnlyTitle && s.select) {
        [self showSelect:s];
    }
    else if (s.action) {
        if ([s.type integerValue] != RRSettingTypeSubSetting) {
            if ([s.action hasSuffix:@":"]) {
                [self mvp_runAction:s.action value:path];
            }
            else {
                [self mvp_runAction:s.action];
            }
        }
        else {
            [self mvp_runAction:s.action value:s];
        }
    }
}

- (void)showSelect:(RRSetting*)setting
{
    __weak typeof(self) weakSelf = self;
    UIAlertController* alert = UI_Alert();
    [setting.select enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        alert.action(obj, ^(UIAlertAction * _Nonnull action, UIAlertController * _Nonnull alert) {
            [weakSelf mvp_runAction:setting.action value:[obj description]];
        });
    }];
    alert.cancel(@"取消", ^(UIAlertAction * _Nonnull action) {
        
    });
    alert.show((id)self.view);
}

- (void)selectFont:(NSString*)select
{
    NSDictionary* fontDict = @{
                                @"苹方细体":@"PingFangSC-Light",
                                @"苹方标准体":@"PingFangSC-Regular",
                                @"思源宋体细体":@"SourceHanSerifCN-Light",
                                };
    NSString* font = fontDict[select];
    if (font) {
        [[NSUserDefaults standardUserDefaults] setObject:font forKey:@"mainFont"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RRCasNeedReload" object:nil userInfo:nil];
    }
}

- (void)selectMainColor:(NSString*)select
{
    NSDictionary* colorDict = @{
                                @"系统":@"#007AFF",
                                @"紫色":@"#BD10E0",
                                @"黑色":@"#303E58",
                                @"橙色":@"#F5A623",
                                @"青色":@"#50E3C2"
                                };
    NSDictionary* colorDictDark = @{
                                @"系统":@"#007AFF",
                                @"紫色":@"#BD10E0",
                                @"黑色":@"#CFD7DB",
                                @"橙色":@"#F5A623",
                                @"青色":@"#50E3C2"
                                };
    NSString* color = colorDict[select];
    NSString* colorDark = colorDictDark[select];
    if (color) {
        [[NSUserDefaults standardUserDefaults] setObject:color forKey:@"mainTintColor"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    if (colorDark) {
        [[NSUserDefaults standardUserDefaults] setObject:colorDark forKey:@"mainTintColorDark"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RRCasNeedReload" object:nil userInfo:nil];
}


- (void)openAbout
{
    id vc = [MVPRouter viewForURL:@"rr://web" withUserInfo:@{@"name":@"什么是RSS.md"}];
    [[self view] mvp_pushViewController:vc];
}

- (void)openSourceList
{
    id vc = [MVPRouter viewForURL:@"rr://web" withUserInfo:@{@"name":@"开源代码.md"}];
    [[self view] mvp_pushViewController:vc];
}

- (void)openWiki
{
    id vc = [MVPRouter viewForURL:@"rr://web" withUserInfo:@{@"name":@"Reader SP说明书.md"}];
    [[self view] mvp_pushViewController:vc];
}

- (void)openVersion
{
    id vc = [MVPRouter viewForURL:@"rr://web" withUserInfo:@{@"name":@"Reader 版本.md"}];
    [[self view] mvp_pushViewController:vc];
}




- (void)feedOffical
{
    if (self.feeding) {
        return;
    }
    self.feeding = YES;
    
    UIViewController* vc = (UIViewController*)[self view];
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc hudWait:@"订阅中"];
    });
    
    id v = [MVPRouter viewForURL:@"rr://feed" withUserInfo:nil];
    id<MVPViewLoadProtocol> tv = nil;
    if ([v conformsToProtocol:@protocol(MVPViewLoadProtocol)]) {
        tv = v;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self view] mvp_pushViewController:v];
    });
    
    __weak typeof(self) weakself = self;
    FMFeedParserOperation* operation = [[RRFeedLoader sharedLoader] loadOfficalWithInfoBlock:^(MWFeedInfo * _Nonnull info) {
        [tv loadData:info];
        
        RRGetWebIconOperation* o = [[RRGetWebIconOperation alloc] init];
        [o setHost:info.url];
        [o setGetIconBlock:^(NSString * _Nonnull icon) {
            [tv loadIcon:icon];
        }];
        [o start];
        
    } itemBlock:^(MWFeedItem * _Nonnull item) {
        //        //NSLog(@"%@",item);
        [tv loadData:item];
        
    } errorBlock:^(NSError * _Nonnull error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [vc hudFail:@"订阅失败"];
            if (v) {
                [weakself.view mvp_popViewController:nil];
            }
        });
        weakself.feeding = NO;
    } finishBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [vc hudDismiss];
        });
        [tv loadFinish];
        weakself.feeding = NO;
    }];
    
    self.currentOperation = operation;
}

- (void)cancelAllOperations
{
    if (self.currentOperation) {
        [self.currentOperation cancel];
        self.feeding = NO;
    }
    
    UIViewController* vc = (UIViewController*)[self view];
    dispatch_async(dispatch_get_main_queue(), ^{
        [vc hudDismiss];
    });
}

- (void)changeNoti:(UISwitch*)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        return;
    }
    //    //NSLog(@"%@",sender);
    if (sender.on == NO) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:self.notiSetting.switchkey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return;
    }
    
    
    __weak typeof(self) weakSelf = self;
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionBadge|UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError * _Nullable error) {
        
        if (!granted) {
            //            //NSLog(@"%@",weakSelf.badgeSetting);
            weakSelf.notiSetting.switchValue = @(NO);
            //            //NSLog(@"%@",self.badgeSetting.switchValue);
            UI_Alert().
            titled(@"请在系统「设置」中开启Reader的通知功能")
            .recommend(@"前往「设置」", ^(UIAlertAction * _Nonnull action, UIAlertController * _Nonnull alert) {
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                if([[UIApplication sharedApplication] canOpenURL:url]) {
                    NSURL*url =[NSURL URLWithString:UIApplicationOpenSettingsURLString];
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                        
                    }];
                }
            })
            .cancel(@"取消", ^(UIAlertAction * _Nonnull action) {
                
            })
            .show((id)weakSelf.view);
            
        }
        else {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:weakSelf.notiSetting.switchkey];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }];
    
}

- (void)changeNotiBadge:(UISwitch*)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:[sender isOn] forKey:self.badgeSetting.switchkey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeEnterUnread:(UISwitch*)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:[sender isOn] forKey:self.enterUnreadSetting.switchkey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeiCloud:(UISwitch*)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:[sender isOn] forKey:self.iCloudSetting.switchkey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)changeToolBack:(UISwitch*)sender
{
    if (![sender isKindOfClass:[UISwitch class]]) {
        return;
    }
    
    [[NSUserDefaults standardUserDefaults] setBool:[sender isOn] forKey:self.toolBackSetting.switchkey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)openOPML
{
    UIDocumentPickerViewController* dvc = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.xml"] inMode:UIDocumentPickerModeImport];
    [[self view] mvp_presentViewController:dvc animated:YES completion:^{
        
    }];
    dvc.delegate = self;
}

- (void)openUISetting:(RRSetting*)set
{
    id vc = [MVPRouter viewForURL:[NSString stringWithFormat:@"rr://setting?setting=%@&title=%@",set.value,set.title] withUserInfo:nil];
    [[self view] mvp_pushViewController:vc];
}

- (void)openiCloud:(RRSetting*)set
{
    id vc = [MVPRouter viewForURL:[NSString stringWithFormat:@"rr://setting?setting=%@&title=%@",set.value,set.title] withUserInfo:nil];
    [[self view] mvp_pushViewController:vc];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    //    NSLog(@"%@",urls);
    OPMLDocument* d = [[RRFeedLoader sharedLoader] loadOPML:urls.firstObject];
    __weak typeof(self) weakSelf = self;
    [d openWithCompletionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                id view = [MVPRouter viewForURL:@"rr://import" withUserInfo:@{@"model":d}];
                [weakSelf.view mvp_pushViewController:view];
            }
            else {
                [self.view hudFail:@"导入文件失败"];
            }
        });
    }];
}

- (RRDataBackuper *)backuper
{
    if (!_backuper) {
        _backuper = [[RRDataBackuper alloc] init];
    }
    return _backuper;
}
 

- (void)rewriteiCloud:(id)sender
{
    if (!self.backuper.iCloudURL) {
        [self.view hudInfo:@"iCloud功能没有开启"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.backuper backupToiCloud:^(BOOL x) {
//        NSLog(@"%s %@",__func__,@(x));
        dispatch_async(dispatch_get_main_queue(), ^{
            if (x) {
                [[weakSelf view] hudSuccess:@"备份成功"];
            }
            else {
                [[weakSelf view] hudSuccess:@"备份失败"];
            }
            [weakSelf.view mvp_reloadData];
        });
    }];
}

- (void)rewriteLocal:(id)sender
{
    if (!self.backuper.iCloudURL) {
        [self.view hudInfo:@"iCloud功能没有开启"];
        return;
    }
    NSArray* files = [self.backuper showiCloudFiles];
    if (files.count > 1) {
        __weak typeof(self) weakSelf = self;
        [self.backuper recoverFromiCloud:^(BOOL x) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (x) {
                    [weakSelf.view hudSuccess:@"恢复成功"];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"RRMainListNeedUpdate" object:nil];
                }
                else {
                    [weakSelf.view hudFail:@"操作失败"];
                }
                [weakSelf.view mvp_reloadData];
            });
        }];
    }
    else {
        [self.view hudInfo:@"没有数据可以恢复"];
    }
}

- (void)syncFromiCloud:(id)sender
{
    if (!self.backuper.iCloudURL) {
        [self.view hudInfo:@"iCloud功能没有开启"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [self.backuper downloadFromiCloud:^(BOOL x) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (x) {
                [[weakSelf view] hudSuccess:@"操作成功"];
            }
            else {
                [[weakSelf view] hudFail:@"操作失败"];
            }
            [weakSelf.view mvp_reloadData];
        });
    }];
}

- (NSString*)hasiCloudBackup
{
    NSArray* a = [self.backuper showiCloudFiles];
    if (a.count > 1) {
        if ([a containsObject:@"Model"]) {
            return @"已同步";
        }
    }
    return @"未同步";
}

- (void)test:(id)sender
{
    [self.backuper showiCloudFiles];
}

- (NSString*)localTime
{
    NSURL* local = [self.backuper localURL];
    return [self dateWithURL:local];
}

- (NSString*)iCloudTime
{
    NSURL* iCloud = [self.backuper iCloudURL];
    return [self dateWithURL:iCloud];
}

- (NSString*)dateWithURL:(NSURL*)url
{
    NSArray* a = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[url path] error:nil];
    if ([a containsObject:@"Model"]) {
//        NSURL* file = [url URLByAppendingPathComponent:@"Model.sqlite"];
        NSURL* file = url;
        NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[file path] error:nil];
        //        NSLog(@"%@",fileAttrs);
        //        return @" ";
        if (fileAttrs) {
            NSDate* date = fileAttrs[@"NSFileModificationDate"];
            NSDateFormatter* f = [[NSDateFormatter alloc] init];
            [f setTimeStyle:NSDateFormatterShortStyle];
            [f setDateStyle:NSDateFormatterShortStyle];
            return [f stringFromDate:date];
        }
        else {
            return @"信息获取失败";
        }
    }
    return @"";
}

- (void)dealloc
{
    NSLog(@"%s",__func__);
}

- (void)paied{
    NSString* paied = [[NSUserDefaults standardUserDefaults] valueForKey:@"paied"];
    if (!paied || paied.length == 0) {
        NSUUID* u = [NSUUID UUID];
        [[NSUserDefaults standardUserDefaults] setValue:u.UUIDString forKey:@"uuid"];
        paied = [[u.UUIDString stringByAppendingString:[UIApplication sharedApplication].bundleID()] sha256String];
        [[NSUserDefaults standardUserDefaults] setValue:paied forKey:@"paied"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (BOOL)isPaied {
    NSString* uuid = [[NSUserDefaults standardUserDefaults] valueForKey:@"uuid"];
    NSString* paied1 = [[uuid stringByAppendingString:[UIApplication sharedApplication].bundleID()] sha256String];
    NSString* paid = [[NSUserDefaults standardUserDefaults] valueForKey:@"paied"];
    return paid && paied1 && [paid isEqualToString:paied1];
}


- (void (^)(SKPaymentTransaction *))purchasedBlock
{
    if (!_purchasedBlock) {
        __weak typeof (self) weakSelf = self;
        _purchasedBlock = ^ (SKPaymentTransaction * t) {
            
            switch (t.transactionState) {
                case SKPaymentTransactionStateFailed:
                {
                    //                    [weakSelf snackMessage:@"购买或恢复失败"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.view hudFail:NSLocalizedString(@"购买或恢复失败", nil)];
                        
                    });
                    break;
                }
                case SKPaymentTransactionStateRestored:
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [weakSelf.view hudSuccess:NSLocalizedString(@"恢复购买成功", nil)];
                        [weakSelf paied];
                    });
                    
                    break;
                }
                case SKPaymentTransactionStatePurchased:
                {
                    //                    [weakSelf snackMessage:];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [PWToastView showText:NSLocalizedString(@"赞助成功，谢谢支持", nil)];
                        [weakSelf paied];
                    });
//                    [weakSelf paied];
                    break;
                }
                default:
                    break;
            }
        
        };
    }
    return _purchasedBlock;
}


- (void)donate
{
    UI_Alert().titled(@"鼓励开发者")
    .recommend([NSString stringWithFormat:@"向开发者赞助 %@",self.donateSetting.value], ^(UIAlertAction * _Nonnull action, UIAlertController * _Nonnull alert) {
//        [AppleAPIHelper ]
        SKProduct* p = [[ApplePurchaseDelegate sharedOne].products firstObject];
        if (p) {
            [[ApplePurchaseDelegate sharedOne] setPurchasedBlock:[self purchasedBlock]];
            [AppleAPIHelper purchaseProduct:p];
        }
        [alert dismissViewControllerAnimated:YES completion:nil];
    })
    .action(@"恢复购买", ^(UIAlertAction * _Nonnull action, UIAlertController * _Nonnull alert) {
        [[ApplePurchaseDelegate sharedOne] setPurchasedBlock:[self purchasedBlock]];
        [AppleAPIHelper restoreProduct];
    })
    .action(@"加入QQ用户群", ^(UIAlertAction * _Nonnull action, UIAlertController * _Nonnull alert) {
        [[UIPasteboard generalPasteboard] setString:@"819888483"];
        [self.view hudSuccess:@"群号已复制"];
    })
    .cancel(@"取消", ^(UIAlertAction * _Nonnull action) {
        
    })
    .show((id)self.view);
}

- (void)feedback
{
    
}

- (void)appstore
{
    [self.view hudWait:@"加载中"];
    __weak typeof(self) weakSelf = self;
    [AppleAPIHelper openAppStore:@"1454638098" vc:(id)[self view] complate:^(BOOL x) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.view hudDismiss];
        });
    }];
}


- (void)exportOPML:(NSIndexPath*)path
{
    if (self.exporting) {
        return;
    }
    self.exporting = YES;
    NSDateFormatter* f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"yy-MM-dd"];
    NSURL* u = [[UIApplication sharedApplication].doucumentDictionary() URLByAppendingPathComponent:[NSString stringWithFormat:@"reader-export-%@.opml",[f stringFromDate:[NSDate date]]]];
    OPMLDocument* d = [[OPMLDocument alloc] initWithFileURL:u];
//    [d addOutlineWithTitle:@"1" title:@"2" type:@"rss" xmlUrl:@"123" htmlUrl:@"321"];
    NSArray* a = [[RPDataManager sharedManager] getAll:@"EntityFeedInfo" predicate:nil key:nil value:nil sort:@"sort" asc:YES];
    if (a.count == 0) {
        self.exporting = NO;
        [self.view hudInfo:@"没有可以导出的订阅源"];
        return;
    }
    else {
        [self.view hudWait:@"处理中"];
    }
    
    [a enumerateObjectsUsingBlock:^(EntityFeedInfo*  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [d addOutlineWithText:obj.summary title:obj.title type:@"rss" xmlUrl:[[obj url] absoluteString] htmlUrl:[obj link]];
    }];
    
    
    MVPTableViewOutput* o = [(id)self.view valueForKey:@"outputer"];
    UITableViewCell* cell = [[o tableview] cellForRowAtIndexPath:path];
    CGRect r = [[o tableview] convertRect:cell.frame toView:[(id)[self view] view]];
    
    
    __weak typeof(self) weakSelf = self;
    [d saveToURL:u forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL success) {
        
        dispatch_async(dispatch_get_main_queue(), ^{
           
            UIActivityViewController* a = [[UIActivityViewController alloc] initWithActivityItems:@[u] applicationActivities:nil];
            
            if([UIDevice currentDevice].iPad())
            {
                a.modalPresentationStyle = UIModalPresentationPopover;
                a.popoverPresentationController.sourceRect = r;
                a.popoverPresentationController.sourceView = [(id)[weakSelf view] view];
                a.popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirectionLeft;
            }
            
            [[weakSelf view] mvp_presentViewController:a animated:YES completion:^{
                [weakSelf.view hudDismiss];
                weakSelf.exporting = NO;
            }];
            
            
        });
    }];
    
}

- (void)openIconSet:(NSString*)title
{
    NSDictionary* iconDict = @{
                                   @"黑底绿标":@"icon1",
                                   @"白底黑标(纯黑)":@"icon2",
                                   @"白底黑标(渐变)":@"icon3",
                                   };
        
    [AppleAPIHelper setIconname:iconDict[title]];
}


@end
