import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import Display
import TelegramCore
import SyncCore
import TelegramUIPreferences
import TelegramBaseController
import OverlayStatusController
import AccountContext
import PresentationDataUtils
import TelegramNotices
import SearchUI
import LanguageSuggestionUI
import ContextUI
import TelegramIntents
import AsyncDisplayKit
import TelegramPresentationData
import ItemListUI
import ActivityIndicator
import ChatListSearchItemNode
import AvatarNode

public final class CircleMenuController: ViewController {
    
    private var closeButton = ASButtonNode()
    private let workspaceNode: CircleWorkspaceNode
    private let context: AccountContext
    private let presentationData: PresentationData
    private let groupSelected: ((PeerGroupId) -> Void)?
    
    init(context: AccountContext, groupSelected: ((PeerGroupId) -> Void)?) {
        self.context = context
        self.workspaceNode = CircleWorkspaceNode(context: context)
        self.groupSelected = groupSelected
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        
        view.backgroundColor = UIColor(white: 0, alpha: 0.4)
        
        view.addSubnode(closeButton)
        closeButton.setTitle("Close", with: Font.semibold(20.0), with: presentationData.theme.actionSheet.standardActionTextColor, for: .normal)
        
        closeButton.addTarget(self, action: #selector(onCancelPressed), forControlEvents: .touchUpInside)
        closeButton.backgroundColor = presentationData.theme.actionSheet.opaqueItemBackgroundColor
        closeButton.layer.cornerRadius = 10
        view.addSubnode(workspaceNode)
        
        self.workspaceNode.groupSelected = onGroupSelected
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let deviceWidth = layout.deviceMetrics.previewingContentSize(inLandscape: false).width
        let containerWidth: CGFloat = deviceWidth - (deviceWidth*0.05)
        let buttonHeight: CGFloat = 50
        let yOffset: CGFloat = 6
        let position = CGPoint(x: (layout.size.width - containerWidth)/2, y: layout.size.height - buttonHeight - yOffset - layout.intrinsicInsets.bottom)
        
        transition.updateFrame(node: self.closeButton,
                               frame: CGRect(x: position.x,
                                             y: position.y,
                                             width: containerWidth, height: buttonHeight))
        
        transition.updateFrame(node: self.workspaceNode,
        frame: CGRect(x: position.x,
                      y: position.y - yOffset ,
                      width: containerWidth, height: 100))
        
        
        workspaceNode.containerLayoutUpdated(layout, transition: transition)
    }
    
    private func onGroupSelected(groupId: PeerGroupId) {
        groupSelected?(groupId)
        onCancelPressed()
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func onCancelPressed() {
         self.dismiss()
     }
}

class CircleWorkspaceNode: ASDisplayNode {
    
    private let context: AccountContext
    
    private let titleTextNode: ASTextNode
    private let descTextNode: ASTextNode
    private let listNode: ListView
    private var createCircleButton: ASButtonNode
    public var groupSelected: ((PeerGroupId) -> Void)?
    
    private let cellHeight: CGFloat = 40
    private var presentationData: PresentationData
    
    private var dequeuedInitialTransitionOnLayout = false
    
    init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        
        self.titleTextNode = ASTextNode()
        self.descTextNode = ASTextNode()
        self.listNode = ListView()
        self.createCircleButton = ASButtonNode()
        
        self.titleTextNode.attributedText = NSAttributedString(string: "Workspaces", font: Font.regular(17.0), textColor: self.presentationData.theme.list.itemPrimaryTextColor, paragraphAlignment: .center)
        self.descTextNode.attributedText = NSAttributedString(string: "Select or add", font: Font.regular(12.0), textColor: .gray, paragraphAlignment: .center)
    
//        self.createCircleButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
        if let plusIcon = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Add"), color: presentationData.theme.actionSheet.standardActionTextColor) {
            self.createCircleButton.setImage(plusIcon, for: [])
            self.createCircleButton.setTitle("Create workspace", with: Font.regular(18.0), with: presentationData.theme.actionSheet.standardActionTextColor, for: [])
            self.createCircleButton.contentHorizontalAlignment = .left
            self.createCircleButton.backgroundColor = presentationData.theme.actionSheet.itemBackgroundColor
            self.createCircleButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 0)
        }
        
        super.init()
        
        self.setViewBlock({
            return UITracingLayerView()
        })
        
        self.layer.cornerRadius = 10
        self.layer.masksToBounds = true
        self.backgroundColor = presentationData.theme.actionSheet.opaqueItemBackgroundColor
        
        self.addSubnode(self.titleTextNode)
        self.addSubnode(self.descTextNode)
        self.addSubnode(self.listNode)
        self.addSubnode(self.createCircleButton)
    }
    
    override func didLoad() {
        super.didLoad()
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(node: titleTextNode, frame: .init(x: 0, y: 10, width: frame.width, height: 25))
        transition.updateFrame(node: descTextNode, frame: .init(x: 0, y: titleTextNode.frame.maxY, width: frame.width, height: 15))
        
        transition.updateFrame(node: listNode, frame: .init(x: 0, y: descTextNode.frame.maxY + 10, width: frame.width, height: 150))
        
        transition.updateFrame(node: createCircleButton, frame: .init(x: 0, y: listNode.frame.maxY, width: frame.width, height: 50))
        transition.updateFrame(node: self, frame: .init(x: frame.origin.x, y: frame.origin.y - createCircleButton.frame.maxY, width: frame.width, height: createCircleButton.frame.maxY))
        
        
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)
        let updateSizeAndInsets = ListViewUpdateSizeAndInsets(size: CGSize(width: frame.width, height: 150), insets: .zero, duration: duration, curve: curve)
        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous], scrollToItem: nil, updateSizeAndInsets: updateSizeAndInsets, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
        
        if !self.dequeuedInitialTransitionOnLayout {
            self.dequeuedInitialTransitionOnLayout = true
            self.dequeueTransition()
        }
    }
    
    private var circleWorkspaceNodeTransition: CircleWorkspaceNodeTransition?
    private var workspacesEntity = [WorkspaceListEntry]()
    private func dequeueTransition() {
        
        let unreadCountsKey = PostboxViewKey.unreadCounts(items: [.total(nil)])
        let counterSignal: Signal<Void, NoError> = context.account.postbox.combinedView(keys: [unreadCountsKey])
        |> mapToSignal { _ in
            return self.context.account.postbox.transaction { transaction in
                transaction.recalculateChatListGroupStats(groupId: .root)
            }
        }
        
        let chatHistoryView: Signal<(ChatListView, ViewUpdateType), NoError> = context.account.viewTracker.tailChatListView(groupId: .root, count: 10)
        
        let transition: Signal<CircleWorkspaceNodeTransition, NoError> = combineLatest(
            Circles.settingsView(postbox: context.account.postbox),
            chatHistoryView,
            context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.inAppNotificationSettings]),
            counterSignal)
            |> map { settings, chatHistory, notificationSetting, _ in
                var unreadStates:[PeerGroupId:PeerGroupUnreadCountersCombinedSummary] = [:]
                for group in chatHistory.0.groupEntries {
                    unreadStates[group.groupId] = group.unreadState
                }
                
                unreadStates[.root] = self.context.account.postbox.groupStats(.root)
                
                let inAppSettings: InAppNotificationSettings
                if let settings = notificationSetting.entries[ApplicationSpecificSharedDataKeys.inAppNotificationSettings] as? InAppNotificationSettings {
                    inAppSettings = settings
                } else {
                    inAppSettings = InAppNotificationSettings.defaultSettings
                }
                
                let toEntity = preparedCircleWorksapceEntity(
                    settings: settings,
                    unreadStates: unreadStates,
                    notificationSettings: inAppSettings)
                
                let transaction = preparedCircleWorkspaceListNodeTransition(presentationData: self.presentationData, from: self.workspacesEntity, to: toEntity, openSearch: { }
                    , selectWorksapce: { (workspacesEntity) in
                    if case let WorkspaceListEntry.workspace(group, title, _, countUnread) = workspacesEntity {
                        self.groupSelected?(group)
                        self.groupSelected = nil
                    }
                }, animated: false)
                
                self.workspacesEntity = toEntity
                return transaction
            } |> deliverOnMainQueue
        
        transition.start(next: { (transaction) in
            self.listNode.transaction(deleteIndices: transaction.deletions, insertIndicesAndItems: transaction.insertions, updateIndicesAndItems: transaction.updates, options: [], updateOpaqueState: nil)
        })
    }

}

private func preparedCircleWorksapceEntity(settings: Circles,
                                           unreadStates: [PeerGroupId:PeerGroupUnreadCountersCombinedSummary],
                                           notificationSettings: InAppNotificationSettings) -> [WorkspaceListEntry] {
    
    let unreadCountDisplayCategory = notificationSettings.totalUnreadCountDisplayCategory
    
    func getUnread(_ groupId: PeerGroupId, type: PeerGroupUnreadCountersCombinedSummary.MuteCategory) -> Int32 {
        if let unread = unreadStates[groupId]?.count(countingCategory: unreadCountDisplayCategory == .chats ? .chats : .messages, mutedCategory: type) {
            return unread
        } else {
            return 0
        }
    }
    
    var workspaces = [WorkspaceListEntry]()
    workspaces.append(.workspace(
        groupId: PeerGroupId.root,
        title: "Personal",
        icon: generateTintedImage(image: UIImage(bundleImageName: "Chat/Input/Search/Members"), color: .gray),
        unread: getUnread(PeerGroupId.root, type: .filtered)
    ))
    
    if settings.groupNames.keys.sorted() == settings.index.keys.sorted() {
        for key in settings.groupNames.keys.sorted(by: {settings.index[$0]! < settings.index[$1]!})  {
            workspaces.append(.workspace(
                groupId: key,
                title: settings.groupNames[key]!,
                icon: nil,
                unread: getUnread(key, type: .filtered)
            ))
        }
    }
    
    workspaces.append(.workspace(
        groupId: .group(Namespaces.PeerGroup.archive.rawValue),
        title: "Archive",
        icon: generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Archive"), color: .gray),
        unread: 0
    ))
    return workspaces
}

private func preparedCircleWorkspaceListNodeTransition(presentationData:PresentationData,
                                                       from fromEntries: [WorkspaceListEntry],
                                                       to toEntries: [WorkspaceListEntry],
                                                       openSearch: @escaping () -> Void,
                                                       selectWorksapce: @escaping (WorkspaceListEntry) -> Void,animated: Bool) -> CircleWorkspaceNodeTransition {
    
    
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map {ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(presentationData: presentationData, searchMode: false, openSearch: openSearch, selectWorkspace: selectWorksapce), directionHint: nil)}
    let updates = updateIndices.map {ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(presentationData: presentationData, searchMode: false, openSearch: openSearch, selectWorkspace: selectWorksapce), directionHint: nil)}
    
    
    
    return CircleWorkspaceNodeTransition(deletions: deletions, insertions: insertions, updates: updates, animated: animated)
}


private enum WorkspaceRecentEntryStableId: Hashable {
    case workspace(PeerGroupId)
    var hashValue: Int {
        switch self {
        case .workspace(let groupId):
            return groupId.hashValue
        }
    }
}
import MergeLists

private struct CircleWorkspaceNodeTransition {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
    let animated: Bool
}

private enum WorkspaceListEntry: Comparable, Identifiable {
    case workspace(groupId: PeerGroupId, title: String, icon: UIImage?, unread: Int32)
    var stableId: WorkspaceRecentEntryStableId {
        switch self {
        case .workspace(let groupId, _, _, _):
            return .workspace(groupId)
        }
    }
    
    static func < (lhs: WorkspaceListEntry, rhs: WorkspaceListEntry) -> Bool {
        lhs.stableId.hashValue < rhs.stableId.hashValue
    }
    

    func item(presentationData: PresentationData, searchMode: Bool, openSearch: @escaping () -> Void, selectWorkspace: @escaping (WorkspaceListEntry) -> Void) -> ListViewItem {
        switch self {
            case let .workspace(groupId, title, icon, unread):
                return CircleWorkspaceListItem(presentationData: ItemListPresentationData(presentationData), title: title, icon: icon, unread: unread, checked: false, activity: false, alwaysPlain: false, action: {
                    selectWorkspace(self)
                })
        }
    }
    
    
}

class CircleWorkspaceListItem: ListViewItem, ItemListItem {
    let sectionId: ItemListSectionId = .zero
    let presentationData: ItemListPresentationData
    let title: String
    let icon: UIImage?
    let unread: Int32
    let checked: Bool
    let activity: Bool
    let alwaysPlain: Bool
    let action: () -> Void
    
    init(presentationData: ItemListPresentationData, title: String, icon: UIImage?, unread: Int32, checked: Bool, activity: Bool, alwaysPlain: Bool, action: @escaping () -> Void) {
        self.presentationData = presentationData
        self.title = title
        self.icon = icon
        self.checked = checked
        self.activity = activity
        self.alwaysPlain = alwaysPlain
        self.action = action
        self.unread = unread
    }
    
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = CircleWorkspaceListItemNode()
            var neighbors = itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem)
            
            let (layout, apply) = node.asyncLayout()(self, params, neighbors)

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply(false) })
                })
            }
        }
    }
    
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? CircleWorkspaceListItemNode {
                let makeLayout = nodeValue.asyncLayout()

                async {
                    var neighbors = itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem)
                    if previousItem == nil || previousItem is ChatListSearchItem || self.alwaysPlain {
                        neighbors.top = .sameSection(alwaysPlain: false)
                    }
                    let (layout, apply) = makeLayout(self, params, neighbors)
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply(animation.isAnimated)
                        })
                    }
                }
            }
        }
    }
    
    var selectable: Bool = true
    
    func selected(listView: ListView){
        listView.clearHighlightAnimated(true)
        self.action()
    }
}


class CircleWorkspaceListItemNode: ItemListRevealOptionsItemNode {
    
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let highlightedBackgroundNode: ASDisplayNode

    private let avatarNode: AvatarNode
    private let iconNode: ASImageNode
    private let iconContainerNode: ASDisplayNode
    private let titleNode: TextNode
    
    private var badgeBackgroundNode: ASImageNode?
    private var badgeTextNode: TextNode?

    private var item: CircleWorkspaceListItem?
    private var layoutParams: (ListViewItemLayoutParams, ItemListNeighbors)?
    private let badgeFont = Font.regular(13.0)

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.iconNode = ASImageNode()
        self.iconNode.isLayerBacked = true
        self.iconNode.displayWithoutProcessing = true
        self.iconNode.displaysAsynchronously = false
        self.iconContainerNode = ASDisplayNode()
        self.iconContainerNode.backgroundColor = #colorLiteral(red: 0.896740557, green: 0.896740557, blue: 0.896740557, alpha: 1)
        self.iconContainerNode.isHidden = true
        
        self.avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 16.0))
        self.avatarNode.isLayerBacked = !smartInvertColorsEnabled()

        self.titleNode = TextNode()
        self.titleNode.isUserInteractionEnabled = false
        self.titleNode.contentMode = .left
        self.titleNode.contentsScale = UIScreenScale

        self.highlightedBackgroundNode = ASDisplayNode()
        self.highlightedBackgroundNode.isLayerBacked = true

        super.init(layerBacked: false, dynamicBounce: false, rotated: false, seeThrough: false)

        self.addSubnode(self.iconContainerNode)
        self.iconContainerNode.addSubnode(self.iconNode)
        self.addSubnode(self.avatarNode)
        self.addSubnode(self.titleNode)
    }
    
    func asyncLayout() -> (_ item: CircleWorkspaceListItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        
        let makeTitleLayout = TextNode.asyncLayout(self.titleNode)
        let makeBadgeTextLayout = TextNode.asyncLayout(self.badgeTextNode)
        
        let currentItem = self.item
        
        return { item, params, neighbors in
            var leftInset: CGFloat = params.leftInset
            let contentInset: CGFloat = 58.0
        
            let insets = UIEdgeInsets.zero
            let titleFont = Font.regular(item.presentationData.fontSize.itemListBaseFontSize)
            leftInset += contentInset

            let (titleLayout, titleApply) = makeTitleLayout(TextNodeLayoutArguments(attributedString: NSAttributedString(string: item.title, font: titleFont, textColor: item.presentationData.theme.list.itemPrimaryTextColor), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: params.width - leftInset - 16.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))

            let separatorHeight = UIScreenPixel

            var updateIconImage: UIImage?
            var updatedTheme: PresentationTheme?

            if currentItem?.presentationData !== item.presentationData.theme {
                updatedTheme = item.presentationData.theme
            }
            
            if currentItem?.icon !== item.icon {
                updateIconImage = item.icon
            }
            
            var badgeTextLayoutAndApply: (TextNodeLayout, () -> TextNode)?
            var currentBadgeBackgroundImage: UIImage?

            let badgeTextColor: UIColor
            if item.unread > 0 {
                currentBadgeBackgroundImage = PresentationResourcesChatList.badgeBackgroundActive(item.presentationData.theme, diameter: 20.0)
                badgeTextColor = item.presentationData.theme.chatList.unreadBadgeActiveTextColor
            } else {
                currentBadgeBackgroundImage = nil
                badgeTextColor = item.presentationData.theme.chatList.unreadBadgeInactiveTextColor
            }
            
            let badgeAttributedString = NSAttributedString(string: item.unread > 0 ? "\(item.unread)" : " ", font: self.badgeFont, textColor: badgeTextColor)
            badgeTextLayoutAndApply = makeBadgeTextLayout(TextNodeLayoutArguments(attributedString: badgeAttributedString, backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: 50.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets()))
            
            
            var badgeSize: CGFloat = 0.0
            if let currentBadgeBackgroundImage = currentBadgeBackgroundImage, let (badgeTextLayout, _) = badgeTextLayoutAndApply {
                badgeSize += max(currentBadgeBackgroundImage.size.width, badgeTextLayout.size.width + 10.0) + 5.0
            }

            var height: CGFloat = 50
            
            let contentSize = CGSize(width: params.width, height: height)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            return (layout, { [weak self] animated in
                if let strongSelf = self {
                    strongSelf.item = item
                    strongSelf.layoutParams = (params, neighbors)

                    let transition: ContainedViewLayoutTransition
                    if animated {
                        transition = .animated(duration: 0.4, curve: .spring)
                    } else {
                        transition = .immediate
                    }
                    
                    let iconSize = CGSize(width: height * 0.7, height: height * 0.7)

                    if let updateIconImage = updateIconImage {
                        strongSelf.iconNode.image = updateIconImage
                        strongSelf.iconContainerNode.isHidden = false
                        strongSelf.iconContainerNode.layer.cornerRadius = iconSize.width/2
                        strongSelf.iconContainerNode.isHidden = false
                        strongSelf.avatarNode.isHidden = true
                    } else {
                        strongSelf.iconContainerNode.isHidden = true
                        strongSelf.avatarNode.isHidden = false
                        strongSelf.avatarNode.setCustomLetters([String(strongSelf.item!.title.prefix(1)).uppercased()], explicitColor: .blue)
                    }
                    
                    let badgeBackgroundWidth: CGFloat
                    if let currentBadgeBackgroundImage = currentBadgeBackgroundImage, let (badgeTextLayout, badgeTextApply) = badgeTextLayoutAndApply {
                        let badgeBackgroundNode: ASImageNode
                        let badgeTransition: ContainedViewLayoutTransition
                        if let current = strongSelf.badgeBackgroundNode {
                            badgeBackgroundNode = current
                            badgeTransition = transition
                        } else {
                            badgeBackgroundNode = ASImageNode()
                            badgeBackgroundNode.isLayerBacked = true
                            badgeBackgroundNode.displaysAsynchronously = false
                            badgeBackgroundNode.displayWithoutProcessing = true
                            strongSelf.addSubnode(badgeBackgroundNode)
                            strongSelf.badgeBackgroundNode = badgeBackgroundNode
                            badgeTransition = .immediate
                        }
                        
                        badgeBackgroundNode.image = currentBadgeBackgroundImage
                        
                        badgeBackgroundWidth = max(badgeTextLayout.size.width + 10.0, currentBadgeBackgroundImage.size.width)
                        let badgeBackgroundFrame = CGRect(x: strongSelf.revealOffset + params.width - params.rightInset - badgeBackgroundWidth - 6.0, y: floor((height - currentBadgeBackgroundImage.size.height) / 2.0), width: badgeBackgroundWidth, height: currentBadgeBackgroundImage.size.height)
                        let badgeTextFrame = CGRect(origin: CGPoint(x: badgeBackgroundFrame.midX - badgeTextLayout.size.width / 2.0, y: badgeBackgroundFrame.minY + 2.0), size: badgeTextLayout.size)
                        
                        let badgeTextNode = badgeTextApply()
                        if badgeTextNode !== strongSelf.badgeTextNode {
                            strongSelf.badgeTextNode?.removeFromSupernode()
                            strongSelf.addSubnode(badgeTextNode)
                            strongSelf.badgeTextNode = badgeTextNode
                        }
                        
                        badgeTransition.updateFrame(node: badgeBackgroundNode, frame: badgeBackgroundFrame)
                        badgeTransition.updateFrame(node: badgeTextNode, frame: badgeTextFrame)
                    } else {
                        badgeBackgroundWidth = 0.0
                        if let badgeBackgroundNode = strongSelf.badgeBackgroundNode {
                            badgeBackgroundNode.removeFromSupernode()
                            strongSelf.badgeBackgroundNode = nil
                        }
                        if let badgeTextNode = strongSelf.badgeTextNode {
                            badgeTextNode.removeFromSupernode()
                            strongSelf.badgeTextNode = badgeTextNode
                        }
                    }
                    
                    
                    if let _ = updatedTheme {
                        strongSelf.backgroundNode.backgroundColor = item.presentationData.theme.list.itemBlocksBackgroundColor
                        strongSelf.highlightedBackgroundNode.backgroundColor = item.presentationData.theme.list.itemHighlightedBackgroundColor
                        strongSelf.bottomStripeNode.backgroundColor = item.presentationData.theme.list.itemBlocksSeparatorColor
                    }

                    let _ = titleApply()

                    let rectIcon = CGRect(origin: CGPoint(x: params.leftInset + floor((contentInset - iconSize.width) / 2.0), y: floor((contentSize.height - iconSize.height) / 2.0)), size: iconSize)
                    
                    if let image = strongSelf.iconNode.image {
                        transition.updateFrame(node: strongSelf.iconContainerNode, frame: rectIcon)
                        
                        let sizeIcon = CGSize(width: rectIcon.size.width * 0.6, height: rectIcon.size.width * 0.6)
                        transition.updateFrame(node: strongSelf.iconNode, frame: CGRect(x: (rectIcon.width - sizeIcon.width)/2, y: (rectIcon.height - sizeIcon.height)/2, width: sizeIcon.width, height: sizeIcon.height))
                    }
                    
                    transition.updateFrame(node: strongSelf.avatarNode, frame: rectIcon)

                    if strongSelf.backgroundNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0)
                    }
                    if strongSelf.topStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1)
                    }
                    if strongSelf.bottomStripeNode.supernode == nil {
                        strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2)
                    }
                    strongSelf.topStripeNode.isHidden = true

                    let bottomStripeInset: CGFloat = 0.0

                    strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                    strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                    strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - bottomStripeInset, height: separatorHeight))

                    transition.updateFrame(node: strongSelf.titleNode, frame: CGRect(origin: CGPoint(x: leftInset, y: (height - titleLayout.size.height)/2), size: titleLayout.size))

                    strongSelf.highlightedBackgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -UIScreenPixel), size: CGSize(width: params.width, height: contentSize.height + UIScreenPixel + UIScreenPixel))
                }
            })
        }
    }

    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)

        if highlighted {
            self.highlightedBackgroundNode.alpha = 1.0
            if self.highlightedBackgroundNode.supernode == nil {
                var anchorNode: ASDisplayNode?
                if self.bottomStripeNode.supernode != nil {
                    anchorNode = self.bottomStripeNode
                } else if self.topStripeNode.supernode != nil {
                    anchorNode = self.topStripeNode
                } else if self.backgroundNode.supernode != nil {
                    anchorNode = self.backgroundNode
                }
                if let anchorNode = anchorNode {
                    self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: anchorNode)
                } else {
                    self.addSubnode(self.highlightedBackgroundNode)
                }
            }
        } else {
            if self.highlightedBackgroundNode.supernode != nil {
                if animated {
                    self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0.0, duration: 0.4, completion: { [weak self] completed in
                        if let strongSelf = self {
                            if completed {
                                strongSelf.highlightedBackgroundNode.removeFromSupernode()
                            }
                        }
                    })
                    self.highlightedBackgroundNode.alpha = 0.0
                } else {
                    self.highlightedBackgroundNode.removeFromSupernode()
                }
            }
        }
    }
    
    override func animateInsertion(_ currentTimestamp: Double, duration: Double, short: Bool) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }
    
    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
    
}
