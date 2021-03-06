// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


import UIKit
import Cartography

// MARK: ArchivedListViewControllerDelegate

@objc protocol ArchivedListViewControllerDelegate: class {
    func archivedListViewControllerWantsToDismiss(controller: ArchivedListViewController)
    func archivedListViewController(controller: ArchivedListViewController, didSelectConversation conversation: ZMConversation)
    func archivedListViewController(controller: ArchivedListViewController, wantsActionMenuForConversation conversation: ZMConversation)
}

// MARK: - ArchivedListViewController

@objc final class ArchivedListViewController: UIViewController {
    
    let collectionView = UICollectionView(frame: CGRectZero, collectionViewLayout: ConversationListCollectionViewLayout())
    let archivedNavigationBar = ArchivedNavigationBar(title: "archived_list.title".localized.uppercaseString)
    let cellReuseIdentifier = "ConversationListCellArchivedIdentifier"
    let swipeIdentifier = "ArchivedList"
    let viewModel = ArchivedListViewModel()
    var initialSyncCompleted: Bool = false
    
    weak var delegate: ArchivedListViewControllerDelegate?
    
    required init() {
        super.init(nibName: nil, bundle: nil)
        ZMUserSession.addInitalSyncCompletionObserver(self)
        viewModel.delegate = self
        createViews()
        createConstraints()
        if let initialSyncCompleted = ZMUserSession.sharedSession().initialSyncOnceCompleted {
            self.initialSyncCompleted = initialSyncCompleted.boolValue
        }
    }
    
    deinit {
        ZMUserSession.removeInitalSyncCompletionObserver(self)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func createViews() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.registerClass(ConversationListCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        collectionView.backgroundColor = .clearColor()
        collectionView.alwaysBounceVertical = true
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        
        [archivedNavigationBar, collectionView].forEach(view.addSubview)
        archivedNavigationBar.dismissButtonHandler = {
            self.delegate?.archivedListViewControllerWantsToDismiss(self)
        }
    }
    
    func createConstraints() {
        constrain(view, archivedNavigationBar, collectionView) { view, navigationBar, collectionView in
            navigationBar.top == view.top
            navigationBar.left == view.left
            navigationBar.right == view.right
            navigationBar.bottom == collectionView.top
            collectionView.left == view.left
            collectionView.bottom == view.bottom
            collectionView.right == view.right
        }
    }
    
}

// MARK: - CollectionViewDelegate

extension ArchivedListViewController: UICollectionViewDelegate {
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        guard let conversation = viewModel[indexPath.row] else { return }
        delegate?.archivedListViewController(self, didSelectConversation: conversation)
    }
    
    func scrollViewDidScroll(scrollView: UIScrollView) {
        let showSeparator = scrollView.contentOffset.y >= 16
        guard showSeparator != archivedNavigationBar.showSeparator else { return }
        archivedNavigationBar.showSeparator = showSeparator
    }
}

// MARK: - CollectionViewDataSource

extension ArchivedListViewController: UICollectionViewDataSource {
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseIdentifier, forIndexPath: indexPath) as! ConversationListCell
        cell.conversation = viewModel[indexPath.row]
        cell.delegate = self
        cell.mutuallyExclusiveSwipeIdentifier = swipeIdentifier
        cell.autoresizingMask = .FlexibleWidth
        return cell
    }
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.count
    }
    
    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 1
    }
    
}

// MARK: - ZMInitialSyncCompletionObserver

extension ArchivedListViewController: ZMInitialSyncCompletionObserver {
    
    func initialSyncCompleted(notification: NSNotification!) {
        initialSyncCompleted = true
        collectionView.reloadData()
    }
    
}

// MARK: - ArchivedListViewModelDelegate

extension ArchivedListViewController: ArchivedListViewModelDelegate {
    
    func archivedListViewModel(model: ArchivedListViewModel, didUpdateArchivedConversationsWithChange change: ConversationListChangeInfo, usingBlock: dispatch_block_t) {
        
        guard initialSyncCompleted else { return }
        let indexPathForItem: Int -> NSIndexPath = { return NSIndexPath(forItem: $0, inSection: 0) }
        
        collectionView.performBatchUpdates({
            usingBlock()
            
            if change.deletedIndexes.count > 0 {
                self.collectionView.deleteItemsAtIndexPaths(change.deletedIndexes.map(indexPathForItem))
            }
            if change.insertedIndexes.count > 0 {
                self.collectionView.insertItemsAtIndexPaths(change.insertedIndexes.map(indexPathForItem))
            }
            change.enumerateMovedIndexes { from, to in
                self.collectionView.moveItemAtIndexPath(indexPathForItem(Int(from)), toIndexPath: indexPathForItem(Int(to)))
            }
        }, completion: nil)
    }
    
    func archivedListViewModel(model: ArchivedListViewModel, didUpdateConversationWithChange change: ConversationChangeInfo) {
        guard initialSyncCompleted else { return }
        guard change.isArchivedChanged || change.conversationListIndicatorChanged || change.nameChanged ||
            change.unreadCountChanged || change.connectionStateChanged || change.isSilencedChanged else { return }
        for case let cell as ConversationListCell in collectionView.visibleCells() where cell.conversation == change.conversation {
            cell.updateAppearance()
        }
    }
    
}

// MARK: - ConversationListCellDelegate

extension ArchivedListViewController: ConversationListCellDelegate {
    func conversationListCellOverscrolled(cell: ConversationListCell!) {
        delegate?.archivedListViewController(self, wantsActionMenuForConversation: cell.conversation)
    }
}
