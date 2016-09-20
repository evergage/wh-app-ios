/*
 * This project constitutes a work of the United States Government and is
 * not subject to domestic copyright protection under 17 USC § 105.
 *
 * However, because the project utilizes code licensed from contributors
 * and other third parties, it therefore is licensed under the MIT
 * License.  http://opensource.org/licenses/mit-license.php.  Under that
 * license, permission is granted free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the conditions that any appropriate copyright notices and this
 * permission notice are included in all copies or substantial portions
 * of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 * LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
 * OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
 * WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
//
//  AppDelegate.m
//  WhiteHouse
//


#import "AppDelegate.h"
#import "SWRevealViewController.h"
#import "LiveViewController.h"
#import "MainViewController.h"
#import "SidebarViewController.h"
#import "AFHTTPRequestOperation.h"
#import "WHFeedItem.h"
#import "FavoritesViewController.h"
#import "DOMParser.h"
#import <Evergage/Evergage.h>


@interface AppDelegate ()<SWRevealViewControllerDelegate>
@property (nonatomic, readonly) NSString *menuPath;
@property (nonatomic, readonly) NSMutableArray<UIImage *> *placeholderImages;
@end


@implementation AppDelegate

- (instancetype)init {
    if (self = [super init]) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _menuPath = [paths.firstObject stringByAppendingPathComponent:@"menuData"];
        _livePath = [paths.firstObject stringByAppendingPathComponent:@"livedata"];
        _placeholderImages = [NSMutableArray arrayWithObjects:
                              [UIImage imageNamed:@"WH_logo_3D_CMYK.png"],
                              [UIImage imageNamed:@"WH_logo_3D_CMYK.png"],
                              [UIImage imageNamed:@"WH_logo_3D_CMYK.png"],
                              [UIImage imageNamed:@"WH_logo_3D_CMYK.png"],
                              [UIImage imageNamed:@"WH_logo_3D_CMYK.png"],
                              nil];
    }
    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    
    [self reloadMenu]; // Creates liveFeed, needed for bg fetch
    self.livePosts = [NSMutableArray arrayWithContentsOfFile:self.livePath]; // So bg fetch discovers if new data or not
    
    if (application.applicationState != UIApplicationStateBackground) {
        [self constructUI];
    }
    
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    return [[Evergage sharedInstance] handleOpenURL:url];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    if (!self.window) {
        [self constructUI];
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self.blogData removeAllObjects];
    [self.photoData removeAllObjects];
    [self.videoData removeAllObjects];
    [self.briefingRoomData removeAllObjects];
}


#pragma mark - Construct UI

- (void)constructUI {
    // Evergage Integration
    Evergage *evergage = [Evergage sharedInstance];
#ifdef DEBUG
    // Development settings
    //evergage.logLevel = EVGLogLevelWarn;
    evergage.logLevel = EVGLogLevelDebug;
    [evergage allowDesignConnections];
#endif
    [evergage startWithEvergageAccountKey:@"demo" dataset:@"whitehouse"];
    
    UIApplication *application = [UIApplication sharedApplication];
    application.statusBarStyle = UIStatusBarStyleLightContent;
    [UINavigationBar appearance].barTintColor = [UIColor colorWithRed:0.0 green:0.2 blue:0.4 alpha:1.0];
    [UINavigationBar appearance].titleTextAttributes = @{NSForegroundColorAttributeName : [UIColor whiteColor]};
    [UINavigationBar appearance].tintColor = [UIColor whiteColor];
    [UINavigationBar appearance].titleTextAttributes = @{
        NSFontAttributeName : [UIFont fontWithName:@"Times" size:20],
        NSForegroundColorAttributeName : [UIColor whiteColor]
    };
    if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        [application registerUserNotificationSettings:
         [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert|UIUserNotificationTypeSound|UIUserNotificationTypeBadge categories:nil]];
    }
    
    application.applicationIconBadgeNumber = 0;
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:@"Main" bundle: nil];
    SWRevealViewController *revealVC = [mainStoryboard instantiateInitialViewController];
    self.window.rootViewController = revealVC;
    [self.window makeKeyAndVisible];
    SidebarViewController *sidebarVC = (SidebarViewController *)revealVC.rearViewController;
    [sidebarVC performSegueWithIdentifier:@"BlogSegue" sender:sidebarVC];
    
    [self fetchMenu];
    [self fetchPlaceholderImages];
    
    // todo: ugh
    LiveViewController *liveViewController = [[LiveViewController alloc]init];
    [liveViewController fetchNewDataWithCompletionHandler:nil];
}


#pragma mark - Menu

- (NSArray<NSDictionary *> *)defaultFeeds {
    return @[
             @{
                 @"title"     : @"Blog",
                 @"view-type" : @"article-list",
                 @"feed-url"  : @"http://www.whitehouse.gov/feed/mobile/blog"
                 },
             @{
                 @"title"     : @"Briefing Room",
                 @"view-type" : @"article-list",
                 @"feed-url"  : @"http://www.whitehouse.gov/feed/mobile/newsroom"
                 },
             @{
                 @"title"     : @"Photos",
                 @"view-type" : @"photo-gallery",
                 @"feed-url"  : @"http://www.whitehouse.gov/feed/mobile/photos"
                 },
             @{
                 @"title"     : @"Videos",
                 @"view-type" : @"video-gallery",
                 @"feed-url"  : @"http://www.whitehouse.gov/feed/mobile/video"
                 },
             @{
                 @"title"     : @"Live",
                 @"view-type" : @"live",
                 @"feed-url"  : @"http://www.whitehouse.gov/feed/mobile/live"
                 },
             ];
}

- (NSArray<NSDictionary *> *)nonFeedMenuItems {
    return @[
             @{
                 @"title"     : @"Favorites",
                 @"view-type" : @"favorites"
                 },
             @{
                 @"title"     : [NSString stringWithFormat:@"%@ Recs", self.useEvergageRecs ? @"Disable" : @"Enable"]
                 },
             @{
                 @"title"     : @"Recommendations",
                 @"view-type" : @"recs"
                 }
             ];
}

- (void)setUseEvergageRecs:(BOOL)useEvergageRecs {
    _useEvergageRecs = useEvergageRecs;
    self.menuItems[self.menuItems.count-2] = @{ @"title" : [NSString stringWithFormat:@"%@ Recs", useEvergageRecs ? @"Disable" : @"Enable"] };
}

- (void)reloadMenu {
    NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithContentsOfFile:self.menuPath];
    if (!items) items = [self defaultFeeds].mutableCopy;
    [items addObjectsFromArray:[self nonFeedMenuItems]];
    self.menuItems = items;
    for (NSDictionary *item in items) {
        if ([@"live" isEqual:item[@"view-type"]]) {
            self.liveFeed = item[@"feed-url"];
            break;
        }
    }
}

- (void)fetchMenu {
    NSString *menuUrl = [NSString stringWithFormat:@"http://www.whitehouse.gov/sites/default/files/feeds/config.json"];
    NSURL *url = [NSURL URLWithString:menuUrl];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    
    __weak typeof(self) weakSelf = self;
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    operation.responseSerializer = [AFJSONResponseSerializer serializer];
    operation.responseSerializer.acceptableContentTypes = [NSSet setWithObject:@"text/plain"];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        NSArray *menuJSON = responseObject[@"feeds"];
        // validate?
        if (![menuJSON writeToFile:strongSelf.menuPath atomically:YES]) {
            NSLog(@"Couldn't save menu config");
        }
        [strongSelf reloadMenu];
        //[strongSelf preloadData];
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"Error fetching menu config");
    }];
    [operation start];
}


#pragma mark - Placeholder Images

- (void)fetchPlaceholderImages {
    for (int i=1; i<=4; i++) {
        NSString *urlString = [NSString stringWithFormat:@"http://www.whitehouse.gov/sites/default/files/app/app_feature_%i.jpg", i];
        NSURL *url = [NSURL URLWithString:urlString];
        
        __weak typeof(self) weakSelf = self;
        [NSURLConnection sendAsynchronousRequest:[NSMutableURLRequest requestWithURL:url]
                                           queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                   UIImage *image = nil;
                                   if (!data || error || !(image = [UIImage imageWithData:data])) return;
                                   [weakSelf.placeholderImages replaceObjectAtIndex:i withObject:image];
                               }];
    }
}

- (nonnull UIImage *)placeholderImageForIndexPath:(nullable NSIndexPath *)indexPath {
    return self.placeholderImages[(indexPath.section + indexPath.row) % self.placeholderImages.count];
}


#pragma mark - Background Fetch Live Feed

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    if (!self.liveFeed) {
        completionHandler(UIBackgroundFetchResultFailed);
        return;
    }
    
    // todo: creating throw-away VCs (done in many places) is awful
    NSDate *fetchStart = [NSDate date];
    LiveViewController *liveViewController = [[LiveViewController alloc] init];
    [liveViewController fetchNewDataWithCompletionHandler:^(UIBackgroundFetchResult result) {
        completionHandler(result);
        
        NSDate *fetchEnd = [NSDate date];
        NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
        NSLog(@"Background Fetch Duration: %f seconds", timeElapsed);
    }];
}


#pragma mark - Notifications

- (void)application:(UIApplication *)app didReceiveLocalNotification:(UILocalNotification *)localNotification {
    self.liveLink = localNotification.userInfo[@"url"];
    if (UIApplicationStateActive == app.applicationState) {
        NSTimeInterval timeUntilStart = localNotification.fireDate.timeIntervalSinceNow;
        if (timeUntilStart > 0 && timeUntilStart < (30*60.0)) {
            [[[UIAlertView alloc] initWithTitle:@"In 30 Minutes"
                                        message:localNotification.alertBody
                                       delegate:nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil]
             show];
        }
    }
}


//#pragma mark - Preload
// sync network calls and making assumptions about menu items/order
//- (void)preloadData {
//    DOMParser * parser = [[DOMParser alloc] init];
//    NSURL *briefingUrl = [[NSURL alloc] initWithString:[[_menuItems objectAtIndex:1] objectForKey:@"feed-url"]];
//    parser.xml = [NSString stringWithContentsOfURL:briefingUrl encoding:NSUTF8StringEncoding error:nil];
//    _briefingRoomData = [[NSMutableArray alloc]init];
//    [_briefingRoomData addObjectsFromArray:[parser parseFeed]];
//    NSURL *photoUrl = [[NSURL alloc] initWithString:[[_menuItems objectAtIndex:2] objectForKey:@"feed-url"]];
//    parser.xml = [NSString stringWithContentsOfURL:photoUrl encoding:NSUTF8StringEncoding error:nil];
//    _photoData = [[NSMutableArray alloc]init];
//    [_photoData addObjectsFromArray:[parser parseFeed]];
//    NSURL *videoUrl = [[NSURL alloc] initWithString:[[_menuItems objectAtIndex:3] objectForKey:@"feed-url"]];
//    parser.xml = [NSString stringWithContentsOfURL:videoUrl encoding:NSUTF8StringEncoding error:nil];
//    _videoData = [[NSMutableArray alloc]init];
//    [_videoData addObjectsFromArray:[parser parseFeed]];
//    // Currently recs are on-demand in the VC and not pre-loaded or saved beyond VC instance
//}



@end
