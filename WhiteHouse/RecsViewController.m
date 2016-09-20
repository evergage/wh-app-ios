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
//  RecsViewController.m
//  WhiteHouse
//

#import "RecsViewController.h"
#import "AppDelegate.h"
#import "WebViewController.h"
#import "PostTableCell.h"
#import "PostCollectionCell.h"
#import "UIKit+AFNetworking.h"
#import "Util.h"
#import <Evergage/Evergage.h>


static const int GUTTER = 25;
static const int CELLS_PER_ROW = 2;


@interface RecsViewController ()
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) NSArray<EVGItem *> *items;
@property (nonatomic, strong) EVGItem *selectedItem;
@end


@implementation RecsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UIColor *blue = [UIColor colorWithRed:0.0 green:0.2 blue:0.4 alpha:1.0];
    [[UINavigationBar appearance] setBarTintColor:blue];
    
    self.title = @"Recommendations";
    
    // Set the side bar button action. When it's tapped, it'll show up the sidebar.
    _sidebarButton.target = self.revealViewController;
    _sidebarButton.action = @selector(revealToggle:);
    
    // Set the gesture
    [self.view addGestureRecognizer:self.revealViewController.panGestureRecognizer];
    
    // fetching data
    [self.tblBlogs setDelegate:self];
    [self.tblBlogs setDataSource:self];
    [self.collectBlogs setDelegate:self];
    [self.collectBlogs setDataSource:self];
    [self.collectBlogsPlus setDelegate:self];
    [self.collectBlogsPlus setDataSource:self];
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    
    [self.refreshControl addTarget:self
                            action:@selector(hardRefresh)
                  forControlEvents:UIControlEventValueChanged];
    
    NSString *deviceType = [UIDevice currentDevice].model;
    // todo: (also main & video VCs)
    // - refreshControl not ever added to collectBlogsPlus. And when rotates...
    // - refreshControl also not operable when no items/recs
    if([deviceType isEqualToString:@"iPad"]){
        [self.collectBlogs addSubview:self.refreshControl];
    }else{
        [self.tblBlogs addSubview:self.refreshControl];
    }
    self.view.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
    self.tblBlogs.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
    [[UITableViewHeaderFooterView appearance] setTintColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]];
    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setTextColor:[UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0]];
    [[UILabel appearanceWhenContainedIn:[UITableViewHeaderFooterView class], nil] setFont:[UIFont fontWithName:@"Times" size:16]];
    [_collectBlogsPlus setBackgroundColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]];
    [_collectBlogs setBackgroundColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]];
    self.edgesForExtendedLayout = UIRectEdgeNone;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    __weak typeof(self) weakSelf = self;
    [self.evergageScreen setCampaignHandler:^(EVGCampaign * _Nonnull campaign) {
        [weakSelf handleCampaign:campaign];
    } forTarget:@"TrendingArticlesRec"];
    [self refreshData];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_tblBlogs reloadData];
    [_collectBlogs reloadData];
    [_collectBlogsPlus reloadData];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [_tblBlogs reloadData];
    [_collectBlogs reloadData];
    [_collectBlogsPlus reloadData];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [_collectBlogsPlus performBatchUpdates:nil completion:nil];
    [_collectBlogs performBatchUpdates:nil completion:nil];
}

- (void)hardRefresh {
    [self refreshData];
}

- (void)refreshData {
    [self.evergageScreen trackAction:@"Get Recs"];
}

- (void)handleCampaign:(EVGCampaign * _Nonnull)campaign {
    NSArray<NSDictionary *> *articlesJson = campaign.data[@"articles"];
    if (!campaign.isControlGroup && articlesJson.count) {
        self.items = [EVGItem fromJSONArray:articlesJson];
    }
    [self.evergageScreen trackImpression:campaign];
    [_tblBlogs reloadData];
    [_collectBlogs reloadData];
    [_collectBlogsPlus reloadData];
    [self.refreshControl endRefreshing];
    self.loadingRecsView.hidden = self.items.count > 0;
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([@"showRecWebSegue" isEqualToString:segue.identifier]) {
        WebViewController *destViewController = segue.destinationViewController;
        destViewController.url = self.selectedItem.url;
        destViewController.title = self.selectedItem.name;
    }
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (CGFloat)tableView:(UITableView * )tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    EVGItem *item = nil;
    if (indexPath.row < self.items.count) item = self.items[indexPath.row];
    
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\?" options:NSRegularExpressionCaseInsensitive error:&error];
    NSString *string = [regex stringByReplacingMatchesInString:item.name options:0 range:NSMakeRange(0,item.name.length) withTemplate:@""];
    CGSize size = [string sizeWithFont:[UIFont fontWithName:@"Helvetica" size:17] constrainedToSize:CGSizeMake(_tblBlogs.frame.size.width, 999) lineBreakMode:NSLineBreakByWordWrapping];
    if (item.imageUrl)
        return size.height + 255;
    else
        return size.height + 40;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    EVGItem *item = nil;
    if (indexPath.row < self.items.count) item = self.items[indexPath.row];
    
    PostTableCell *cell;
    NSURL *imageURL = [NSURL URLWithString:item.imageUrl];
    if (imageURL) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"BlogCell" forIndexPath:indexPath];
        [cell.backgroundImage setImageWithURL:imageURL placeholderImage:[appDelegate placeholderImageForIndexPath:indexPath]];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"BlogCellNoImage" forIndexPath:indexPath];
    }
    
    cell.titleLabel.text = item.name;
    cell.dateLabel.text = nil;
    if (item.published) cell.dateLabel.text = [Util userVisibleShortStringForDate:item.published];
    cell.card.layer.shadowColor = [UIColor blackColor].CGColor;
    cell.card.layer.shadowRadius = 1;
    cell.card.layer.shadowOpacity = 0.2;
    cell.card.layer.shadowOffset = CGSizeMake(0.2, 2);
    cell.card.layer.masksToBounds = NO;
    [cell setBackgroundColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedItem = nil;
    if (indexPath.row >= self.items.count) return;
    
    self.selectedItem = self.items[indexPath.row];
    [self performSegueWithIdentifier:@"showRecWebSegue" sender:self];
}

#pragma mark - Collection View

- (NSInteger) collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    AppDelegate *appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    
    EVGItem *item = nil;
    if (indexPath.row < self.items.count) item = self.items[indexPath.row];
    
    // Always use image cell since no descriptionLabel text for NoImage
    PostCollectionCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"BlogColCell" forIndexPath:indexPath];
    NSURL *imageURL = [NSURL URLWithString:item.imageUrl]; // May be nil
    [cell.backgroundImage setImageWithURL:imageURL placeholderImage:[appDelegate placeholderImageForIndexPath:indexPath]];
    
    cell.descriptionLabel.text = nil;
    cell.titleLabel.text = item.name;
    cell.dateLabel.text = item.published ? [Util userVisibleShortStringForDate:item.published] : nil;
    cell.layer.shadowColor = [UIColor blackColor].CGColor;
    cell.layer.shadowRadius = 1;
    cell.layer.shadowOpacity = 0.2;
    cell.layer.shadowOffset = CGSizeMake(0.2, 2);
    cell.layer.masksToBounds = NO;
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    self.selectedItem = nil;
    if (indexPath.row >= self.items.count) return;
    
    self.selectedItem = self.items[indexPath.row];
    [self performSegueWithIdentifier:@"showRecWebSegue" sender:self];
}

#pragma mark UICollectionViewDelegate layout

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    int totalGutterWidth = (CELLS_PER_ROW + 1) * GUTTER;
    int cellSize = (self.view.frame.size.width - totalGutterWidth) / CELLS_PER_ROW;
    CGSize c = CGSizeMake(cellSize , cellSize);
    return c;
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView
                        layout:(UICollectionViewLayout*)collectionViewLayout
        insetForSectionAtIndex:(NSInteger)section {
    return UIEdgeInsetsMake(GUTTER, GUTTER, GUTTER, GUTTER);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return GUTTER;
}



@end
