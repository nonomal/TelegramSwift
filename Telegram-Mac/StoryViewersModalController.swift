//
//  StoryViewersModalController.swift
//  Telegram
//
//  Created by Mike Renoir on 19.05.2023.
//  Copyright © 2023 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox


private final class StoryViewerEmptyRowItem : GeneralRowItem {
    fileprivate let state: State
    fileprivate let openPremium: ()->Void
    fileprivate let context: AccountContext
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let sticker: LocalAnimatedSticker = LocalAnimatedSticker.duck_empty
    fileprivate let text: TextViewLayout
    fileprivate let premiumText: TextViewLayout?
    init(_ initialSize: NSSize, height: CGFloat, stableId: AnyHashable, presentation: TelegramPresentationTheme, context: AccountContext, state: State, openPremium: @escaping()->Void) {
        self.openPremium = openPremium
        self.state = state
        self.context = context
        self.presentation = presentation
        self.text = .init(.initialize(string: strings().storyAlertViewsExpired, color: presentation.colors.grayText, font: .normal(.text)), alignment: .center)
        
        if !context.isPremium {
            let attr = parseMarkdownIntoAttributedString(strings().storyViewersPremiumUnlock, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: presentation.colors.grayText), bold: MarkdownAttributeSet(font: .medium(.text), textColor: presentation.colors.grayText), link: MarkdownAttributeSet(font: .medium(.text), textColor: presentation.colors.link), linkAttribute: { contents in
                return (NSAttributedString.Key.link.rawValue, inAppLink.callback(contents, { value in
                    openPremium()
                }))
            }))
            
            self.premiumText = .init(attr, alignment: .center)
            self.premiumText?.interactions = globalLinkExecutor
        } else {
            self.premiumText = nil
        }
        
        super.init(initialSize, height: height, stableId: stableId)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.text.measure(width: width - 40)
        self.premiumText?.measure(width: width - 40)
        
        return true
    }
    
    override func viewClass() -> AnyClass {
        return StoryViewerEmptyRowView.self
    }
}

private final class StoryViewerEmptyRowView : TableRowView {
    private let textView = TextView()
    private let imageView: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 120, 120))
    private let container = View()
    private var button: TitleButton?
    private var premiumText: TextView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.addSubview(imageView)
        container.addSubview(textView)
        addSubview(container)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? StoryViewerEmptyRowItem else {
            return
        }
        var size = imageView.frame.size

        let params = item.sticker.parameters

        imageView.update(with: item.sticker.file, size: imageView.frame.size, context: item.context, parent: nil, table: item.table, parameters: params, animated: animated, positionFlags: nil, approximateSynchronousValue: false)

        textView.update(item.text)
        size.height += textView.frame.height + 10
        
        if let premiumText = item.premiumText {
            let current: TextView
            if let view = self.premiumText {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = true
                current.isSelectable = false
                self.premiumText = current
                container.addSubview(current)
            }
            current.update(premiumText)
            size.height += current.frame.height + 10
        } else {
            if let premiumText = self.premiumText {
                performSubviewRemoval(premiumText, animated: animated)
                self.premiumText = nil
            }
            if let button = self.button {
                performSubviewRemoval(button, animated: animated)
                self.button = nil
            }
        }
        
        if !item.context.isPremium {
            let current: TitleButton
            if let view = self.button {
                current = view
            } else {
                current = TitleButton()
                current.scaleOnClick = true
                current.autohighlight = false
                self.button = current
                container.addSubview(current)
                
            }
            
            current.removeAllHandlers()
            current.set(handler: { [weak item] _ in
                item?.openPremium()
            }, for: .Click)

            current.set(text: strings().storyViewersPremiumLearnMore, for: .Normal)
            current.set(background: item.presentation.colors.accent, for: .Normal)
            current.set(font: .medium(.title), for: .Normal)
            current.set(color: item.presentation.colors.underSelectedColor, for: .Normal)
            current.sizeToFit(NSMakeSize(40, 20))
            current.layer?.cornerRadius = .cornerRadius
            
            size.height += current.frame.height + 20
        } else {
            if let premiumText = self.premiumText {
                performSubviewRemoval(premiumText, animated: animated)
                self.premiumText = nil
            }
            if let button = self.button {
                performSubviewRemoval(button, animated: animated)
                self.button = nil
            }
        }
        
        let views = [imageView, textView, button, premiumText].compactMap({ $0 }).map { $0.frame.width }
        size.width = views.max()!
        container.setFrameSize(size)
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        imageView.centerX(y: 0)
        container.center()
        textView.centerX(y: imageView.frame.maxY + 10)
        if let text = self.premiumText {
            text.centerX(y: textView.frame.maxY + 10)
            if let button = self.button {
                button.centerX(y: text.frame.maxY + 20)
            }
        }
    }
}


private final class StoryViewerRowItem : GeneralRowItem {
    fileprivate let context: AccountContext
    fileprivate let peer: Peer
    fileprivate let reaction: MessageReaction.Reaction?
    fileprivate let storyStats: PeerStoryStats?
    fileprivate let avatarComponent: AvatarStoryIndicatorComponent?
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let nameLayout: TextViewLayout
    fileprivate let dateLayout: TextViewLayout
    fileprivate let callback: (PeerId)->Void
    fileprivate let openStory:(PeerId)->Void
    fileprivate let contextMenu:(PeerId)->Signal<[ContextMenuItem], NoError>
    init(_ initialSize: NSSize, stableId: AnyHashable, context: AccountContext, peer: Peer, reaction: MessageReaction.Reaction?, storyStats: PeerStoryStats?, timestamp: Int32, presentation: TelegramPresentationTheme, callback:@escaping(PeerId)->Void, openStory:@escaping(PeerId)->Void, contextMenu:@escaping(PeerId)->Signal<[ContextMenuItem], NoError>) {
        self.context = context
        self.peer = peer
        self.openStory = openStory
        self.storyStats = storyStats
        self.callback = callback
        self.presentation = presentation
        self.contextMenu = contextMenu
        self.reaction = reaction
        self.nameLayout = .init(.initialize(string: peer.displayTitle, color: presentation.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
        
        
        let string = stringForRelativeTimestamp(relativeTimestamp: timestamp, relativeTo: context.timestamp)

        self.dateLayout = .init(.initialize(string: string, color: presentation.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        
        if let stats = storyStats {
            self.avatarComponent = .init(stats: stats, presentation: presentation)
        } else {
            self.avatarComponent = nil
        }

        super.init(initialSize, stableId: stableId, viewType: .legacy)
        
        _ = makeSize(initialSize.width)
    }
    
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return contextMenu(self.peer.id)
    }
    
    override var menuPresentation: AppMenu.Presentation {
        return .init(colors: storyTheme.colors)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        nameLayout.measure(width: width - 36 - 16 - 16 - 10 - (peer.isPremium ? 20 : 0) - (reaction != nil ? 30 : 0))
        dateLayout.measure(width: width - 36 - 16 - 16 - 10 - 18 - (reaction != nil ? 30 : 0))

        return true
    }
    
    override var height: CGFloat {
        return 52
    }
    
    override func viewClass() -> AnyClass {
        return StoryViewerRowView.self
    }
}

private final class StoryViewerRowView: GeneralRowView {
    fileprivate let avatar = AvatarStoryControl(font: .avatar(12), size: NSMakeSize(36, 36))
    private let container = Control(frame: NSMakeRect(16, 8, 36, 36))
    private let title = TextView()
    private let date = TextView()
    private let stateIcon = ImageView()
    private let borderView = View()
    private let content = Control()
    private var statusControl: PremiumStatusControl?
    private var reaction: InlineStickerItemLayer?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(content)
        container.addSubview(avatar)
        content.addSubview(container)
        content.addSubview(date)
        content.addSubview(title)
        content.addSubview(stateIcon)
        content.addSubview(borderView)
        
        date.userInteractionEnabled = false
        date.isSelectable = false
        
        title.userInteractionEnabled = false
        title.isSelectable = false

        stateIcon.isEventLess = true
        
        avatar.frame = NSMakeRect(0, 0, 36, 36)
        
        content.set(handler: { [weak self] _ in
            if let item = self?.item as? StoryViewerRowItem {
                item.callback(item.peer.id)
            }
        }, for: .Click)
        
        self.container.set(handler: { [weak self] _ in
            if let item = self?.item as? StoryViewerRowItem {
                item.openStory(item.peer.id)
            }
        }, for: .Click)
        avatar.userInteractionEnabled = false
        container.scaleOnClick = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    private var myReaction: MessageReaction.Reaction?
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StoryViewerRowItem else {
            return
        }
        
        let control = PremiumStatusControl.control(item.peer, account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, isSelected: false, cached: self.statusControl, animated: animated)
        if let control = control {
            self.statusControl = control
            self.content.addSubview(control)
        } else if let view = self.statusControl {
            performSubviewRemoval(view, animated: animated)
            self.statusControl = nil
        }
        
        stateIcon.image = item.presentation.icons.story_view_read
        stateIcon.sizeToFit()
        
        self.date.update(item.dateLayout)
        self.title.update(item.nameLayout)
        self.borderView.backgroundColor = item.presentation.colors.border
        
        self.avatar.setPeer(account: item.context.account, peer: item.peer)
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        
        if let reaction = item.reaction {
            if self.myReaction != reaction {
                if let view = self.reaction {
                    performSublayerRemoval(view, animated: false)
                    self.reaction = nil
                }
                let layer = makeView(reaction, context: item.context)
                if let layer = layer {
                    layer.frame = NSMakeRect(frame.width - 25 - container.frame.minX, (frame.height - 25) / 2, 25, 25)
                    self.layer?.addSublayer(layer)
                    layer.isPlayable = false
                }
                self.myReaction = reaction
                self.reaction = layer
            }
            
        } else if let view = self.reaction {
            performSublayerRemoval(view, animated: animated)
            self.reaction = nil
            self.myReaction = nil
        }
        
        if let component = item.avatarComponent {
            self.avatar.update(component: component, availableSize: NSMakeSize(30, 30), transition: transition)
        } else {
            self.avatar.update(component: nil, availableSize: NSMakeSize(36, 36), transition: transition)
        }
        
        self.container.userInteractionEnabled = item.avatarComponent != nil
    }
    
    private func makeView(_ reaction: MessageReaction.Reaction, context: AccountContext, appear: Bool = false) -> InlineStickerItemLayer? {
        let layer: InlineStickerItemLayer?
        let size = NSMakeSize(25, 25)
        switch reaction {
        case let .custom(fileId):
            layer = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: size, playPolicy: .onceEnd)
        case .builtin:
            if let animation = context.reactions.available?.reactions.first(where: { $0.value == reaction }) {
                let file = appear ? animation.activateAnimation : animation.selectAnimation
                layer = InlineStickerItemLayer(account: context.account, file: file, size: size, playPolicy: .onceEnd)
            } else {
                layer = nil
            }
        }
        
        return layer
    }


    
    func setOpenProgress(_ signal:Signal<Never, NoError>) {
        SetOpenStoryDisposable(self.avatar.pushLoadingStatus(signal: signal))
    }
    
    override func layout() {
        super.layout()
        
        content.frame = bounds
        
        let contentX = container.frame.maxX + 10
        
        
        title.setFrameOrigin(NSMakePoint(contentX, 10))
        date.setFrameOrigin(NSMakePoint(contentX + 18, frame.height - date.frame.height - 10))

        
        statusControl?.setFrameOrigin(NSMakePoint(title.frame.maxX + 3, 10))

        stateIcon.setFrameOrigin(NSMakePoint(contentX, frame.height - stateIcon.frame.height - 10))
        
        borderView.frame = NSMakeRect(contentX, frame.height - .borderSize, frame.width - contentX, .borderSize)
    }
}

private final class Arguments {
    let context: AccountContext
    let presentation: TelegramPresentationTheme
    let callback:(PeerId)->Void
    let openStory:(PeerId)->Void
    let contextMenu:(PeerId)->Signal<[ContextMenuItem], NoError>
    let toggleListMode:(EngineStoryViewListContext.ListMode)->Void
    let openPremium:()->Void
    init(context: AccountContext, presentation: TelegramPresentationTheme, callback: @escaping(PeerId)->Void, openStory:@escaping(PeerId)->Void, contextMenu:@escaping(PeerId)->Signal<[ContextMenuItem], NoError>, toggleListMode:@escaping(EngineStoryViewListContext.ListMode)->Void, openPremium:@escaping()->Void) {
        self.context = context
        self.presentation = presentation
        self.callback = callback
        self.openStory = openStory
        self.contextMenu = contextMenu
        self.toggleListMode = toggleListMode
        self.openPremium = openPremium
    }
}


private struct State : Equatable {
    var item: EngineStoryItem
    var views: EngineStoryViewListContext.State?
    var isLoadingMore: Bool = false
    var listMode: EngineStoryViewListContext.ListMode
    var sortMode: EngineStoryViewListContext.SortMode
    var query: String = ""
}


private func _id_peer(_ id:PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_\(id.toInt64())")
}
private func _id_miss(_ id: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_miss\(id)")
}
private let _id_loading_more = InputDataIdentifier("_id_loading_more")
private let _id_empty = InputDataIdentifier("_id_empty")
private let _id_empty_holder = InputDataIdentifier("_id_empty_holder")
private let _id_not_recorded_text = InputDataIdentifier("_id_not_recorded_text")
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    
    struct Tuple: Equatable {
        let peer: PeerEquatable
        let reaction: MessageReaction.Reaction?
        let storyStats: PeerStoryStats?
        let timestamp: Int32
        let viewType: GeneralViewType
    }
  
    var needToLoad: Bool = true
    
    if let list = state.views {
        
        var items: [Tuple] = []
        if !arguments.context.isPremium, state.item.views?.reactedCount == 0 {
            
        } else {
            for item in list.items {
                items.append(.init(peer: .init(item.peer._asPeer()), reaction: item.reaction, storyStats: item.storyStats, timestamp: item.timestamp, viewType: .legacy))
            }
        }
        
        for item in items {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(item.peer.peer.id), equatable: InputDataEquatable(item), comparable: nil, item: { initialSize, stableId in
                return StoryViewerRowItem(initialSize, stableId: stableId, context: arguments.context, peer: item.peer.peer, reaction: item.reaction, storyStats: item.storyStats, timestamp: item.timestamp, presentation: arguments.presentation, callback: arguments.callback, openStory: arguments.openStory, contextMenu: arguments.contextMenu)
            }))
            index += 1
        }
        
        let expired = state.item.expirationTimestamp + 24 * 60 * 60 < arguments.context.timestamp && !arguments.context.isPremium
        
        var totalHeight: CGFloat = 450
        let totalCount = state.item.views?.seenCount ?? 0
        if totalCount > 15 && !expired {
            totalHeight -= 40
        }
        
        
        if items.isEmpty {
            if !state.query.isEmpty || state.listMode != .everyone {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_empty, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                    return SearchEmptyRowItem(initialSize, stableId: stableId, height: totalHeight, icon: arguments.presentation.icons.emptySearch, customTheme: .initialize(arguments.presentation))
                }))
            } else {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_empty_holder, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                    return StoryViewerEmptyRowItem(initialSize, height: totalHeight, stableId: stableId, presentation: arguments.presentation, context: arguments.context, state: state, openPremium: arguments.openPremium)
                }))
            }
            
        } else {
            var additionHeight: CGFloat = 0
            if state.listMode == .everyone, state.query.isEmpty {
                if state.views?.totalCount == items.count, state.item.views?.seenCount != state.views?.totalCount {
                    let text: String
                    if arguments.context.isPremium {
                        text = strings().storyViewersNotRecorded
                    } else {
                        text = strings().storyViewersPremiumUnlock
                    }
                    let viewType: GeneralViewType = .modern(position: .single, insets: .init())
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_not_recorded_text, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                        return GeneralTextRowItem(initialSize, height: 40, text: .markdown(text, linkHandler: { _ in
                            arguments.openPremium()
                        }), textColor: arguments.presentation.colors.grayText, alignment: .center, centerViewAlignment: true, viewType: viewType)
                    }))
                    additionHeight += 40
                    
                }
            }
            
            
            let miss = totalHeight - (CGFloat(items.count) * 52.0 + additionHeight)
            if miss > 0 {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_miss(0), equatable: .init(miss), comparable: nil, item: { initialSize, stableId in
                    return GeneralRowItem(initialSize, height: miss, stableId: stableId, backgroundColor: storyTheme.colors.background)
                }))
                index += 1
            }
        }
    }
    
    // entries
    return entries
}

private final class StoryViewersTopView : View {
    fileprivate let segmentControl: CatalinaStyledSegmentController
    fileprivate let titleView = TextView()
    fileprivate let close = ImageButton()
    fileprivate let filter = ImageButton()
    fileprivate let search: SearchView
    
    private var arguments: Arguments?
    
    private let top: View
    private let bottom: View
    required init(frame frameRect: NSRect) {
        self.search = .init(frame: NSMakeRect(0, 10, frameRect.width, 30))
        search.searchTheme = storyTheme.search
        self.top = View(frame: NSMakeRect(0, 0, frameRect.width, 50))
        self.bottom = View(frame: NSMakeRect(0, 50, frameRect.width, 40))
        self.segmentControl = CatalinaStyledSegmentController(frame: NSMakeRect(0, 0, 240, 30))
        super.init(frame: frameRect)
        
        segmentControl.add(segment: .init(title: strings().storyViewersAll, handler: { [weak self] in
            self?.arguments?.toggleListMode(.everyone)
        }))
        
        segmentControl.add(segment: .init(title: strings().storyViewersContacts, handler: { [weak self] in
            self?.arguments?.toggleListMode(.contacts)
        }))
        
        close.set(image: NSImage(named: "Icon_ChatAction_Close")!.precomposed(storyTheme.colors.text), for: .Normal)
        close.autohighlight = false
        close.scaleOnClick = true
        close.sizeToFit()
        
        filter.set(image: NSImage(named: "Icon_StoryViewers_Filter")!.precomposed(storyTheme.colors.text), for: .Normal)
        filter.autohighlight = false
        filter.scaleOnClick = true
        filter.sizeToFit()
        
        self.backgroundColor = storyTheme.colors.background
        self.borderColor = storyTheme.colors.border
        self.border = [.Bottom]
        
        
        segmentControl.theme = CatalinaSegmentTheme(backgroundColor: storyTheme.colors.listBackground, foregroundColor: storyTheme.colors.background, activeTextColor: storyTheme.colors.text, inactiveTextColor: storyTheme.colors.listGrayText)

        
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        
        top.addSubview(titleView)
        top.addSubview(close)
        top.addSubview(filter)
        top.addSubview(segmentControl.view)
        
        bottom.addSubview(search)
        
        addSubview(top)
        addSubview(bottom)
    }
    
    func update(_ state: State, arguments: Arguments) {
        self.arguments = arguments
        let string = strings().storyViewsTitleCountable(state.item.views?.seenCount ?? 0)
        let layout = TextViewLayout(.initialize(string: string, color: storyTheme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        self.titleView.update(layout)
        
        let totalCount = state.item.views?.seenCount ?? 0
        let totalLikes = state.item.views?.reactedCount ?? 0
        let expired = state.item.expirationTimestamp + 24 * 60 * 60 < arguments.context.timestamp && !arguments.context.isPremium
        let onlyTitle = (state.item.privacy != nil && state.item.privacy?.base != .everyone) || expired

        segmentControl.view.isHidden = totalCount <= 20 || onlyTitle
        titleView.isHidden = totalCount > 20 && !onlyTitle
        filter.isHidden = totalLikes < 10 || totalLikes == totalCount || expired
        search.isHidden = totalCount < 15 || expired
        needsLayout = true

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        top.frame = NSMakeRect(0, 0, frame.width, 50)
        bottom.frame = NSMakeRect(0, top.frame.maxY, frame.width, 50)
        segmentControl.view.center()
        close.centerY(x: 15)
        filter.centerY(x: top.frame.width - filter.frame.width - 15)
        search.frame = NSMakeRect(15, 0, frame.width - 30, 30)
        titleView.center()
    }
    
}

func StoryViewersModalController(context: AccountContext, list: EngineStoryViewListContext, peerId: PeerId, story: EngineStoryItem, presentation: TelegramPresentationTheme, callback:@escaping(PeerId)->Void) -> InputDataModalController {
    
    
    let initialViews = story.views ?? .init(seenCount: 0, reactedCount: 0, seenPeers: [], hasList: false)
    
    var storyViewList = list
    
    let storyContext: Promise<EngineStoryViewListContext> = Promise(storyViewList)
    
    let actionsDisposable = DisposableSet()

    let initialState = State(item: story, views: nil, listMode: .everyone, sortMode: .reactionsFirst)
    
    let statePromise: ValuePromise<State> = ValuePromise(ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil
    
    var getControl:((PeerId)->NSView?)? = nil
    var setProgress:((PeerId, Signal<Never, NoError>)->Void)? = nil

    let arguments = Arguments(context: context, presentation: presentation, callback: { peerId in
        callback(peerId)
        close?()
    }, openStory: { peerId in
        StoryModalController.ShowStories(context: context, isHidden: false, initialId: .init(peerId: peerId, id: nil, messageId: nil, takeControl: { [] peerId, _, _ in
            return getControl?(peerId)
        }, setProgress: { value in
            setProgress?(peerId, value)
        }), singlePeer: true)
    }, contextMenu: { peerId in
        return combineLatest(getCachedDataView(peerId: peerId, postbox: context.account.postbox), context.account.viewTracker.peerView(peerId)) |> take(1) |> map { cachedData, peerView in
            var items: [ContextMenuItem] = []
            if let view = cachedData as? CachedUserData, let peer = peerViewMainPeer(peerView) {
                let blockedFromStories = view.flags.contains(.isBlockedFromStories)
                items.append(ContextMenuItem(blockedFromStories ? strings().storyViewContextMenuShowMyStories(peer.compactDisplayTitle) : strings().storyViewContextMenuHideMyStories(peer.compactDisplayTitle), handler: {
                    let text: String
                    if blockedFromStories {
                        _ = context.storiesBlockedPeersContext.remove(peerId: peerId).start()
                        text = strings().storyViewTooltipShowMyStories(peer.compactDisplayTitle)
                    } else {
                        _ = context.storiesBlockedPeersContext.add(peerId: peerId).start()
                        text = strings().storyViewTooltipHideMyStories(peer.compactDisplayTitle)
                    }
                    showModalText(for: context.window, text: text)
                }, itemImage: MenuAnimation.menu_stories.value))
                
                items.append(ContextSeparatorItem())
                
                
                if peerView.peerIsContact {
                    items.append(ContextMenuItem(strings().storyViewContextMenuDeleteContact, handler: {
                        let text: String = strings().storyViewTooltipDeleteContact(peer.compactDisplayTitle)
                        _ = context.engine.contacts.deleteContactPeerInteractively(peerId: peerId).start()
                        showModalText(for: context.window, text: text)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                } else {
                    items.append(ContextMenuItem(view.isBlocked ? strings().storyViewContextMenuUnblock : strings().storyViewContextMenuBlock, handler: {
                        let text: String
                        if view.isBlocked {
                            _ = context.blockedPeersContext.remove(peerId: peerId).start()
                            text = strings().storyViewTooltipUnblock(peer.compactDisplayTitle)
                        } else {
                            _ = context.blockedPeersContext.add(peerId: peerId).start()
                            text = strings().storyViewTooltipBlock(peer.compactDisplayTitle)
                        }
                        showModalText(for: context.window, text: text)
                    }, itemMode: !view.isBlocked ? .destruct : .normal, itemImage: view.isBlocked ? MenuAnimation.menu_unblock.value : MenuAnimation.menu_delete.value))
                }
            }
            return items
        }
    }, toggleListMode: { mode in
        updateState { current in
            var current = current
            current.listMode = mode
            return current
        }
    }, openPremium: {
        showModal(with: PremiumBoardingController(context: context, source: .story_viewers, openFeatures: true, presentation: storyTheme), for: context.window)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    
    let seenCount = (story.views?.seenCount ?? 0)
    let expired = story.expirationTimestamp + 24 * 60 * 60 < arguments.context.timestamp && !arguments.context.isPremium

    let view = StoryViewersTopView(frame: NSMakeRect(0, 0, controller.frame.width, seenCount > 15 && !expired ? 90 : 50))
    controller.contextObject = view
    
    let updateContext:()->Void = {
        let listMode = stateValue.with { $0.listMode }
        let sortMode = stateValue.with { $0.sortMode }
        let query = stateValue.with { $0.query.isEmpty ? nil : $0.query }
        
        var parentSource: EngineStoryViewListContext?
        if query == nil {
            parentSource = list
        } else {
            parentSource = storyViewList
        }
        let contextList: EngineStoryViewListContext
        if listMode == .everyone, sortMode == .reactionsFirst, query == nil {
            contextList = list
        } else {
            contextList = context.engine.messages.storyViewList(id: story.id, views: initialViews, listMode: listMode, sortMode: sortMode, searchQuery: query, parentSource: parentSource)
        }
        storyContext.set(.single(contextList))
    }

    view.search.searchInteractions = .init({ state, animated in
        updateState { current in
            var current = current
            current.query = state.request
            return current
        }
    }, { state in
        updateState { current in
            var current = current
            current.query = state.request
            return current
        }
    })
    
    
    
    view.filter.contextMenu = {
        let menu = ContextMenu(presentation: .current(storyTheme.colors))
        menu.addItem(ContextMenuItem(strings().storyViewersReactionsFirst, handler: {
            updateState { current in
                var current = current
                current.sortMode = .reactionsFirst
                return current
            }
        }, itemImage: MenuAnimation.menu_check_selected.value))
        
        menu.addItem(ContextMenuItem(strings().storyViewersRecentFirst, handler: {
            updateState { current in
                var current = current
                current.sortMode = .recentFirst
                return current
            }
        }))
        return menu
    }
    
    view.close.set(handler: { _ in
        close?()
    }, for: .Click)
    
    controller.getBackgroundColor = {
        presentation.colors.background
    }
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let modalController = InputDataModalController(controller, modalInteractions: nil, size: NSMakeSize(350, 300))
    
    modalController.getModalTheme = {
        .init(text: presentation.colors.text, grayText: presentation.colors.grayText, background: presentation.colors.background, border: presentation.colors.border)
    }

    close = { [weak modalController] in
        modalController?.close()
    }
    
    let loadMore:()->Void = {
        storyViewList.loadMore()
    }
    
    let contextSignal: Signal<(EngineStoryViewListContext, EngineStoryViewListContext.State), NoError> = (storyContext.get() |> mapToSignal { context in
        return context.state |> map {
            (context, $0)
        }
    })
    
    actionsDisposable.add(contextSignal.start(next: { context, list in
        updateState { current in
            var current = current
            current.views = list
            return current
        }
        storyViewList = context
        loadMore()
    }))
    
    var previous = stateValue.with { $0 }
    actionsDisposable.add(statePromise.get().start(next: { value in
        if previous.query != value.query || previous.sortMode != value.sortMode || previous.listMode != value.listMode {
            updateContext()
        }
        previous = value
    }))
    
    
    controller._externalFirstResponder = { [weak view] in
        if let view = view, !view.search.isHidden  {
            return view.search.input
        } else {
            return nil
        }
    }
    
    controller._becomeFirstResponder = {
        return false
    }
    
    controller.afterViewDidLoad = { [weak view, weak modalController] in
        
        if let view = view {
            controller.genericView.set(view)
            modalController?.viewDidResized(.zero)
        }
    }
    
    controller.didLoaded = { controller, _ in
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                loadMore()
            default:
                break
            }
        }
        
        
        getControl = { [weak controller] peerId in
            var control: NSView?
            controller?.tableView.enumerateVisibleItems(with: { item in
                if let item = item as? StoryViewerRowItem, item.peer.id == peerId {
                    control = (item.view as? StoryViewerRowView)?.avatar
                }
                return control == nil
            })
            return control
        }
        setProgress = { [weak controller] peerId, signal in
            controller?.tableView.enumerateVisibleItems(with: { item in
                if let item = item as? StoryViewerRowItem, item.peer.id == peerId {
                    (item.view as? StoryViewerRowView)?.setOpenProgress(signal)
                    return false
                }
                return true
            })
        }
    }
    
    controller.didAppear = { controller in        
        controller.window?.set(handler: { _ in
            return .invokeNext
        }, with: controller, for: .All, priority: .modal)
        
        controller.window?.set(handler: {  _ in
            close?()
            return .invoked
        }, with: controller, for: .DownArrow, priority: .modal)
        
        controller.window?.set(handler: {  _ in
            close?()
            return .invoked
        }, with: controller, for: .Escape, priority: .modal)
        
        controller.tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: true, { [weak controller] scroll in
            var refreshStoryPeerIds:[PeerId] = []
            controller?.tableView.enumerateVisibleItems(with: { item in
                if let item = item as? StoryViewerRowItem {
                    refreshStoryPeerIds.append(item.peer.id)
                }
                return true
            })
            context.account.viewTracker.refreshStoryStatsForPeerIds(peerIds: refreshStoryPeerIds)
        }))
    }
    
    controller.afterTransaction = { [weak view] _ in
        view?.update(stateValue.with { $0 }, arguments: arguments)
    }
    
    loadMore()
    
    return modalController
}



