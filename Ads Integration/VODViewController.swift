//
//  VODViewController.swift
//  Ads Integration
//
//  Created by Manuel on 05/10/20.
//  Copyright © 2020 com.molvera. All rights reserved.
//

import AVFoundation
import UIKit
import GoogleInteractiveMediaAds

class VODViewController: UIViewController, IMAAdsLoaderDelegate, IMAAdsManagerDelegate {

    static let ContentURLString = "https://tkx.apis.anvato.net/rest/v2/mcp/video/456240?anvack=52OJ4YKLM1m8tRFpFLK5nohJ6nwRQlan&eud=2CX1CVqMALRWtTbkmFJdEICLi6bgT64NYR74C5xU%2FEUznZxJ2Azmu%2F5UbhlPwCTzOXy7lSii8sfugqSS6gRTcg%3D%3D"
    
  var adsLoader: IMAAdsLoader!
  var adDisplayContainer: IMAAdDisplayContainer!
  var adsManager: IMAAdsManager!
  var contentPlayhead: IMAAVPlayerContentPlayhead?
  var playerViewController: AVPlayerViewController!
  var adBreakActive = false

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.view.backgroundColor = UIColor.black
    
    setUpContentPlayer()
    setUpAdsLoader()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    requestAds()
  }
    override func viewWillDisappear(_ animated: Bool) {
        self.playerViewController.player?.pause()
        self.playerViewController.player?.rate = 0
        self.playerViewController.player = nil
        
        super.viewWillDisappear(animated)
    }

  func setUpContentPlayer() {
    // Load AVPlayer with path to our content.
    let contentURL = URL(string: VODViewController.ContentURLString)!
    let player = AVPlayer(url: contentURL)
    
    playerViewController = AVPlayerViewController()
    playerViewController.player = player

    // Set up our content playhead and contentComplete callback.
    contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: player)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(VODViewController.contentDidFinishPlaying(_:)),
      name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
      object: player.currentItem)

    showContentPlayer()
  }

  func showContentPlayer() {
    self.addChildViewController(playerViewController)
    playerViewController.view.frame = self.view.bounds
    self.view.insertSubview(playerViewController.view, at: 0)
    playerViewController.didMove(toParentViewController: self)
  }

  func hideContentPlayer() {
    // The whole controller needs to be detached so that it doesn't capture resume
    // events from the remote and play content underneath the ad.
    playerViewController.willMove(toParentViewController: nil)
    playerViewController.view.removeFromSuperview()
    playerViewController.removeFromParentViewController()
  }

  func setUpAdsLoader() {
    adsLoader = IMAAdsLoader(settings: nil)
    adsLoader.delegate = self
  }

  func requestAds() {
    // Create ad display container for ad rendering.
    adDisplayContainer = IMAAdDisplayContainer(adContainer: self.view)
    let fullString = "https://pubads.g.doubleclick.net/gampad/ads?iu=/5644/televisanews.information.tvapp/apple-tv&description_url=[placeholder]&tfcd=0&npa=0&sz=640x360&gdfp_req=1&output=vast&unviewed_position_start=1&env=vp&impl=s&correlator="
    
    let request = IMAAdsRequest(
      adTagUrl: fullString,
      adDisplayContainer: adDisplayContainer,
      contentPlayhead: contentPlayhead,
      userContext: nil)

    adsLoader.requestAds(with: request)
    
    print(request?.adTagUrl)
  }

  @objc func contentDidFinishPlaying(_ notification: Notification) {
    print("did finish")
    adsLoader.contentComplete()
  }

  // MARK: - UIFocusEnvironment

  override var preferredFocusEnvironments: [UIFocusEnvironment] {
    if adBreakActive {
      // Send focus to the ad display container during an ad break.
//      return [adDisplayContainer.focusEnvironment!]
        print("break active")
    } else {
      // Send focus to the content player otherwise.
      print("else")
    }
    return [playerViewController]
  }

  // MARK: - IMAAdsLoaderDelegate

  func adsLoader(_ loader: IMAAdsLoader!, adsLoadedWith adsLoadedData: IMAAdsLoadedData!) {
    // Grab the instance of the IMAAdsManager and set ourselves as the delegate.
    adsManager = adsLoadedData.adsManager
    adsManager.delegate = self
    adsManager.initialize(with: nil)
  }

  func adsLoader(_ loader: IMAAdsLoader!, failedWith adErrorData: IMAAdLoadingErrorData!) {
    print("Error loading ads: \(String(describing: adErrorData.adError.message))")
    showContentPlayer()
    playerViewController.player?.play()
  }

  // MARK: - IMAAdsManagerDelegate

  func adsManager(_ adsManager: IMAAdsManager!, didReceive event: IMAAdEvent!) {
    switch event.type {
    case IMAAdEventType.LOADED:
      // Play each ad once it has been loaded.
      adsManager.start()
    default:
      break
    }
  }

  func adsManager(_ adsManager: IMAAdsManager!, didReceive error: IMAAdError!) {
    // Fall back to playing content
    print("AdsManager error: \(String(describing: error.message))")
    showContentPlayer()
    playerViewController.player?.play()
  }

  func adsManagerDidRequestContentPause(_ adsManager: IMAAdsManager!) {
    // Pause the content for the SDK to play ads.
    playerViewController.player?.pause()
    hideContentPlayer()
    // Trigger an update to send focus to the ad display container.
    adBreakActive = true
    setNeedsFocusUpdate()
  }

  func adsManagerDidRequestContentResume(_ adsManager: IMAAdsManager!) {
    // Resume the content since the SDK is done playing ads (at least for now).
    showContentPlayer()
    playerViewController.player?.play()
    // Trigger an update to send focus to the content player.
    adBreakActive = false
    setNeedsFocusUpdate()
  }
}
