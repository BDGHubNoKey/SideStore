//
//  NewsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices
import Combine

import AltStoreCore
import Roxas

import Nuke

private final class AppBannerFooterView: UICollectionReusableView
{
    let bannerView = AppBannerView(frame: .zero)
    let tapGestureRecognizer = UITapGestureRecognizer(target: nil, action: nil)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.addGestureRecognizer(self.tapGestureRecognizer)
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.bannerView)
        
        NSLayoutConstraint.activate([
            self.bannerView.topAnchor.constraint(equalTo: self.topAnchor),
            self.bannerView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.bannerView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            self.bannerView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor)
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class NewsViewController: UICollectionViewController, PeekPopPreviewing
{
    // Nil == Show news from all sources.
    var source: Source?
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)
    private var retryButton: UIButton!
    
    private var prototypeCell: NewsCollectionViewCell!
    
    // Cache
    private var cachedCellSizes = [String: CGSize]()
    private var cancellables = Set<AnyCancellable>()
    
    init?(source: Source?, coder: NSCoder)
    {
        self.source = source
        
        super.init(coder: coder)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(NewsViewController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.backgroundColor = .altBackground
        
        self.prototypeCell = NewsCollectionViewCell.instantiate(with: NewsCollectionViewCell.nib!)
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Need to add dummy constraint + layout subviews before we can remove Interface Builder's width constraint.
        self.prototypeCell.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        self.prototypeCell.layoutIfNeeded()
        
        let constraints = self.prototypeCell.constraintsAffectingLayout(for: .horizontal)
        for constraint in constraints where constraint.identifier?.contains("Encapsulated-Layout-Width") == true
        {
            self.prototypeCell.removeConstraint(constraint)
        }
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(AppBannerFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner")
        
        (self as PeekPopPreviewing).registerForPreviewing(with: self, sourceView: self.collectionView)
        
        let refreshControl = UIRefreshControl(frame: .zero)
        refreshControl.addTarget(self, action: #selector(NewsViewController.updateSources), for: .primaryActionTriggered)
        self.collectionView.refreshControl = refreshControl
        
        self.retryButton = UIButton(type: .system)
        self.retryButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.retryButton.setTitle(NSLocalizedString("Try Again", comment: ""), for: .normal)
        self.retryButton.addTarget(self, action: #selector(NewsViewController.updateSources), for: .primaryActionTriggered)
        self.placeholderView.stackView.addArrangedSubview(self.retryButton)
        
        if let source = self.source
        {
            let tintColor = source.effectiveTintColor ?? .altPrimary
            self.view.tintColor = tintColor
            
            let appearance = NavigationBarAppearance()
            appearance.configureWithTintColor(tintColor)
            appearance.configureWithDefaultBackground()
            
            let edgeAppearance = appearance.copy()
            edgeAppearance.configureWithTransparentBackground()
            
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = edgeAppearance
        }
        
        self.preparePipeline()
        self.update()
    }
    
    override func viewWillLayoutSubviews()
    {
        super.viewWillLayoutSubviews()
        
        if self.collectionView.contentInset.bottom != 20
        {
            // Triggers collection view update in iOS 13, which crashes if we do it in viewDidLoad()
            // since the database might not be loaded yet.
            self.collectionView.contentInset.bottom = 20
        }
    }
}

private extension NewsViewController
{
    func preparePipeline()
    {
        AppManager.shared.$updateSourcesResult
            .receive(on: RunLoop.main) // Delay to next run loop so we receive _current_ value (not previous value).
            .sink { result in
                self.update()
            }
            .store(in: &self.cancellables)
    }
    
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>
    {
        let fetchRequest = NewsItem.sortedFetchRequest(for: self.source)
        let context = self.source?.managedObjectContext ?? DatabaseManager.shared.viewContext
        
        // Use fetchedResultsController to split NewsItems up into sections.
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: #keyPath(NewsItem.objectID), cacheName: nil)
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, newsItem, indexPath) in
            guard let self else { return }
            
            let cell = cell as! NewsCollectionViewCell
            cell.contentView.layoutMargins.left = self.view.layoutMargins.left
            cell.contentView.layoutMargins.right = self.view.layoutMargins.right
            
            cell.titleLabel.text = newsItem.title
            cell.captionLabel.text = newsItem.caption
            cell.contentBackgroundView.backgroundColor = newsItem.tintColor
            
            cell.imageView.image = nil
            
            if newsItem.imageURL != nil
            {
                cell.imageView.isIndicatingActivity = true
                cell.imageView.isHidden = false
            }
            else
            {
                cell.imageView.isIndicatingActivity = false
                cell.imageView.isHidden = true
            }
            
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = (cell.titleLabel.text ?? "") + ". " + (cell.captionLabel.text ?? "")
            
            if newsItem.storeApp != nil || newsItem.externalURL != nil
            {
                cell.accessibilityTraits.insert(.button)
            }
            else
            {
                cell.accessibilityTraits.remove(.button)
            }
        }
        dataSource.prefetchHandler = { (newsItem, indexPath, completionHandler) in
            guard let imageURL = newsItem.imageURL else { return nil }
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil) { result in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! NewsCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        dataSource.placeholderView = self.placeholderView
        
        return dataSource
    }
    
    @objc func updateSources()
    {
        AppManager.shared.updateAllSources() { result in
            self.collectionView.refreshControl?.endRefreshing()
            
            guard case .failure(let error) = result else { return }
            
            if self.dataSource.itemCount > 0
            {
                let toastView = ToastView(error: error)
                toastView.addTarget(nil, action: #selector(TabBarController.presentSources), for: .touchUpInside)
                toastView.show(in: self)
            }
        }
    }
    
    func update()
    {
        switch AppManager.shared.updateSourcesResult
        {
        case nil:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")
            
            self.retryButton.isHidden = true
            self.placeholderView.activityIndicatorView.startAnimating()
            
        case .failure(let error):
            self.placeholderView.textLabel.isHidden = false
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch News", comment: "")
            self.placeholderView.detailTextLabel.text = error.localizedDescription
            
            self.retryButton.isHidden = false
            self.placeholderView.activityIndicatorView.stopAnimating()
            
        case .success:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = true
            
            self.retryButton.isHidden = true
            self.placeholderView.activityIndicatorView.stopAnimating()
        }
    }
}

private extension NewsViewController
{
    @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer)
    {
        guard let footerView = gestureRecognizer.view as? UICollectionReusableView else { return }
        
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView == footerView
        }) else { return }
        
        let item = self.dataSource.item(at: indexPath)
        guard let storeApp = item.storeApp else { return }
        
        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
    
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView?.frame.contains(point) ?? false
        }) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        guard let storeApp = app.storeApp else { return }
        
        // if let installedApp = storeApp.installedApp, !installedApp.isUpdateAvailable
        if let installedApp = storeApp.installedApp, !installedApp.hasUpdate
        {
            self.open(installedApp)
        }
        else
        {
            self.install(storeApp, at: indexPath)
        }
    }
    
    @objc func install(_ storeApp: StoreApp, at indexPath: IndexPath)
    {
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        Task<Void, Never>(priority: .userInitiated) { @MainActor in
            // if let installedApp = storeApp.installedApp, installedApp.isUpdateAvailable
            if let installedApp = storeApp.installedApp, installedApp.hasUpdate
            {
                AppManager.shared.update(installedApp, presentingViewController: self, completionHandler: finish(_:))
            }
            else
            {
                await AppManager.shared.installAsync(storeApp, presentingViewController: self, completionHandler: finish(_:))
            }
            
            UIView.performWithoutAnimation {
                self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
            }
        }
        
        @MainActor
        func finish(_ result: Result<InstalledApp, Error>)
        {
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled): break // Ignore
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.opensErrorLog = true
                    toastView.show(in: self)

                case .success: print("Installed app:", storeApp.bundleIdentifier)
                }
                
                UIView.performWithoutAnimation {
                    self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
                }
            }
        }
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

private extension NewsViewController
{
    @objc func importApp(_ notification: Notification)
    {
        self.presentedViewController?.dismiss(animated: true, completion: nil)
    }
}

// Fix the NewsViewController.swift file by adding missing closing braces
extension NewsViewController: UIViewControllerPreviewingDelegate
{
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        guard let indexPaths = self.collectionView.indexPathsForVisibleItems else { return nil }
        
        for indexPath in indexPaths
        {
            guard let cell = self.collectionView.cellForItem(at: indexPath) else { continue }
            
            let convertedPoint = self.collectionView.convert(location, to: cell)
            if cell.bounds.contains(convertedPoint)
            {
                guard let item = self.dataSource.item(at: indexPath) else { return nil }
                
                previewingContext.sourceRect = cell.frame
                
                if let storeApp = item.storeApp
                {
                    let appViewController = AppViewController.makeAppViewController(app: storeApp)
                    return appViewController
                }
            }
        }
        
        // Check if tapping on "View All" footer.
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let layoutAttributes = self.collectionView.layoutAttributesForItem(at: indexPath)
            return layoutAttributes?.frame.maxY ?? 0 > location.y
        }) else { return nil }
        
        guard let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath) else { return nil }
        
        let convertedPoint = self.collectionView.convert(location, to: nil)
        if layoutAttributes.frame.contains(convertedPoint)
        {
            guard let storeApp = item.storeApp else { return nil }
            
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
        }
        
        return nil
    }
    
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        if let appViewController = viewControllerToCommit as? AppViewController
        {
            self.present(appViewController, animated: true, completion: nil)
        }
        else
        {
            self.show(viewControllerToCommit, sender: self)
        }
    }
}
}
}
}
