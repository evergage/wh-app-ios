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
//  LiveViewController.m
//  WhiteHouse
//

#import "LiveViewController.h"
#import "DOMParser.h"
#import "WebViewController.h"
#import "Post.h"
#import "AppDelegate.h"
#import "PostTableCell.h"
#import "Constants.h"
#import "Util.h"

@interface LiveViewController ()
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSArray<Post *> *arrNewsData;
@property (nonatomic, strong) NSArray<NSArray<Post *> *> *arrNewsDataSorted;
@end

@implementation LiveViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.sidebarButton.target = self.revealViewController;
    self.sidebarButton.action = @selector(revealToggle:);
    
    [self.view addGestureRecognizer:self.revealViewController.panGestureRecognizer];
    
    self.tblNews.delegate = self;
    self.tblNews.dataSource = self;
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self
                            action:@selector(refreshData)
                  forControlEvents:UIControlEventValueChanged];
    [self.tblNews addSubview:self.refreshControl];
    
    NSMutableArray<Post *> *posts = [[NSMutableArray alloc] init];
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    for (NSDictionary *postJSON in appDelegate.livePosts) {
        [posts addObject:[Post postFromDictionary:postJSON]];
    }
    [self updateUIWithPosts:posts];
    
    // todo: detect if bg refresh disabled
//    [self refreshData];    <=== this being commented forces app to rely on background refresh
    
    UIImageView *tempImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"seal-bg.png"]];
    tempImageView.contentMode = UIViewContentModeScaleAspectFill;
    [tempImageView setFrame:self.tblNews.frame];
    
    self.tblNews.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.tblNews.backgroundView = tempImageView;
    
    [[UITableViewHeaderFooterView appearance] setTintColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]];
    self.view.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];

    self.edgesForExtendedLayout = UIRectEdgeNone;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
    [self.tblNews reloadData];
    self.title = @"Live";
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self.tblNews reloadData];
}

- (void)refreshData {
    [self fetchNewDataWithCompletionHandler:nil];
}

- (void)updateUIWithPosts:(NSArray<Post *> *)posts {
    self.arrNewsData = posts;
    DOMParser *parser = [[DOMParser alloc] init];
    self.arrNewsDataSorted = [parser sectionPostsByToday:posts];
    self.noLiveEventsView.hidden = posts.count;
    [self.tblNews reloadData];
}

#pragma mark - Fetch
// todo: fetching & data storage should probably be in some data/cache class, shouldn't be creating VC instance just to fetch and not render

- (void)fetchNewDataWithCompletionHandler:(nullable void (^)(UIBackgroundFetchResult))completionHandler {
    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
    NSURL *url = [[NSURL alloc] initWithString:appDelegate.liveFeed];
    DOMParser *parser = [[DOMParser alloc] init];
    // todo: not on main!
    parser.xml = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    [self.refreshControl endRefreshing];
    NSArray<Post *> *posts = [parser parseFeed];
    
    if (posts.count == 0) {
        NSLog(@"Failed to fetch new live data.");
        if (completionHandler) completionHandler(UIBackgroundFetchResultFailed);
        return;
    }
    
    if (appDelegate.livePosts.count && [posts.firstObject.title isEqual:appDelegate.livePosts.firstObject[@"title"]]) {
        NSLog(@"No new live data found.");
        if (completionHandler) completionHandler(UIBackgroundFetchResultNoData);
        return;
    }
    
    NSLog(@"New live data was fetched.");
    [self updateUIWithPosts:posts];
    
    UIApplication *app = [UIApplication sharedApplication];
    if (app.applicationState == UIApplicationStateBackground) {
        app.applicationIconBadgeNumber = posts.count;
    }
    
    NSMutableArray<NSDictionary *> *postsJSON = [[NSMutableArray alloc] init];
    for (Post *post in posts) {
        [postsJSON addObject:[Post dictionaryFromPost:post]];
    }
    if (![postsJSON writeToFile:appDelegate.livePath atomically:YES]) {
        NSLog(@"Couldn't save data.");
    }
    appDelegate.livePosts = postsJSON;
    
    for (Post *d in posts) {
        NSDate *date = [Util dateFromFeedDateString:d.pubDate];
        if (date.timeIntervalSinceNow > 0) {
            UILocalNotification* localNotification = [[UILocalNotification alloc] init];
            localNotification.fireDate = [date dateByAddingTimeInterval:(-30 * 60)]; // Subtract 30 minutes from date
            localNotification.alertBody = [Post stringByStrippingHTML:d.title];
            localNotification.userInfo = @{
                                           @"title" : d.title ?: @"",
                                           @"url" : d.link ?: @"",
                                           };
            [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
        }
    }
    
    if (completionHandler) completionHandler(UIBackgroundFetchResultNewData);
}


#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.arrNewsDataSorted.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section >= self.arrNewsDataSorted.count) return 0;
    return self.arrNewsDataSorted[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return @"Today";
        case 1:
            return @"Upcoming Events";
        default:
            return @"Prior Events";
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section >= self.arrNewsDataSorted.count) return 0;
    if (self.arrNewsDataSorted[section].count) return 20;
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PostTableCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LiveCell" forIndexPath:indexPath];
    
    Post *post = nil;
    if (indexPath.section < self.arrNewsDataSorted.count) {
        NSArray *postsForSection = self.arrNewsDataSorted[indexPath.section];
        if (indexPath.row < postsForSection.count) post = postsForSection[indexPath.row];
    }
    
    cell.titleLabel.text = [self parseString:post.title];
    cell.dateLabel.text = post ? [NSString stringWithFormat:@"%@ - %@", post.getDate, post.getTime] : @"";
    cell.card.layer.shadowColor = [UIColor blackColor].CGColor;
    cell.card.layer.shadowRadius = 1;
    cell.card.layer.shadowOpacity = 0.2;
    cell.card.layer.shadowOffset = CGSizeMake(0.2, 2);
    cell.card.layer.masksToBounds = NO;
    cell.backgroundColor = [UIColor clearColor];
    
    NSDate *postDate = [Util dateFromFeedDateString:post.pubDate];
    NSTimeInterval timeSincePost = postDate.timeIntervalSinceNow;
    if (timeSincePost >= 0 && timeSincePost <= (30 * 60.0)) {
        cell.happeningNowLabel.text = @"Happening Now";
    } else {
        cell.happeningNowLabel.text = @"";
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (IS_IOS_8_OR_LATER)
        return UITableViewAutomaticDimension;
    else {
        NSArray *set = [self.arrNewsDataSorted objectAtIndex:indexPath.section];
        Post *post = [set objectAtIndex:indexPath.row];
        NSString *title = [Post stringByStrippingHTML:post.title];
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\?" options:NSRegularExpressionCaseInsensitive error:&error];
        NSString *string = [regex stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, [title length]) withTemplate:@""];
        CGSize size = [string sizeWithFont:[UIFont fontWithName:@"Helvetica" size:17] constrainedToSize:CGSizeMake(self.tblNews.frame.size.width, 999) lineBreakMode:NSLineBreakByWordWrapping];
        return size.height + 40;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self performSegueWithIdentifier:@"LiveSegue" sender:self];
}

#pragma mark -

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    Post *post = nil;
    NSIndexPath *indexPath = self.tblNews.indexPathForSelectedRow;
    if (indexPath && indexPath.section < self.arrNewsDataSorted.count) {
        NSArray *postsForSection = self.arrNewsDataSorted[indexPath.section];
        if (indexPath.row < postsForSection.count) post = postsForSection[indexPath.row];
    }
    
    WebViewController *destViewController = segue.destinationViewController;
    destViewController.url = post.link;
    NSLog(@"%@", post.link);
    destViewController.title = [self parseString:post.title];
    self.title = @"";
}

// todo: why not standardized decoding, and why not done once in Post construction?
- (NSString*)parseString:(NSString*)str {
    str  = [str stringByReplacingOccurrencesOfString:@"&ndash;" withString:@"-"];
    str  = [str stringByReplacingOccurrencesOfString:@"&rdquo;" withString:@"\""];
    str  = [str stringByReplacingOccurrencesOfString:@"&ldquo;" withString:@"\""];
    str  = [str stringByReplacingOccurrencesOfString:@"&oacute;" withString:@"o"];
    str  = [str stringByReplacingOccurrencesOfString:@"&#039;" withString:@"'"];
    return str;
}

@end
