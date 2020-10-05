//
//  DAIViewController.swift
//  Ads Integration
//
//  Created by Manuel on 05/10/20.
//  Copyright © 2020 com.molvera. All rights reserved.
//

import AVFoundation
import GoogleInteractiveMediaAds
import UIKit

class DAIViewController: UIViewController, IMAAdsLoaderDelegate, IMAStreamManagerDelegate, AVPlayerViewControllerDelegate, IMAAVPlayerVideoDisplayDelegate {

    public var stream: Stream?
        private var adsLoader: IMAAdsLoader?
        private var adContainerView: UIView?
        private var streamManager: IMAStreamManager?
        private var contentPlayhead: IMAAVPlayerContentPlayhead?
        private var playerViewController: AVPlayerViewController?
        private var userSeekTime = 0.0
        private var streams = [Stream]()

      deinit {
        NotificationCenter.default.removeObserver(self)
      }

      override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .black
        
        streams = [LiveStream(name: "Live Stream", assetKey: "sN_IYUG8STe1ZzhIIE_ksA")]
        
        stream = streams[0]
        
        setupAdsLoader()
        
        setupPlayer()
        
        setupAdContainer()

      }

      override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestStream()
      }

      override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        playerViewController!.player?.pause()
        playerViewController!.player?.replaceCurrentItem(with: nil)
      }

      func setupAdsLoader() {
        adsLoader = IMAAdsLoader(settings: nil)
        adsLoader!.delegate = self
      }

      func setupPlayer() {
        let player = AVPlayer()
        playerViewController = AVPlayerViewController()
        playerViewController!.delegate = self
        playerViewController!.player = player

        // Set up our content playhead and contentComplete callback.
        contentPlayhead = IMAAVPlayerContentPlayhead(avPlayer: player)
        NotificationCenter.default.addObserver(self, selector: #selector(self.contentDidFinishPlaying(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: player.currentItem)

        self.addChildViewController(playerViewController!)
        playerViewController!.view.frame = self.view.bounds
        self.view.insertSubview(playerViewController!.view, at: 0)
        playerViewController!.didMove(toParentViewController:self)
      }

      func setupAdContainer() {
        // Attach the ad container to the view hierarchy on top of the player.
        adContainerView = UIView()
        self.view.addSubview(self.adContainerView!)
        self.adContainerView!.frame = self.view.bounds
        // Keep hidden initially, until an ad break.
        self.adContainerView!.isHidden = true
      }

      func requestStream() {
        let videoDisplay = IMAAVPlayerVideoDisplay(avPlayer: self.playerViewController!.player)
        videoDisplay!.playerVideoDisplayDelegate = self
        let adDisplayContainer = IMAAdDisplayContainer(adContainer: self.adContainerView!)
        let request: IMAStreamRequest
        if let liveStream = self.stream as? LiveStream {
          request = IMALiveStreamRequest(assetKey: liveStream.assetKey,
                                         adDisplayContainer: adDisplayContainer,
                                         videoDisplay: videoDisplay)
          self.adsLoader!.requestStream(with: request)
        } else {
          assertionFailure("Unknown stream type selected")
          self.dismiss(animated: false, completion: nil)
        }

      }

      @objc func contentDidFinishPlaying(_ notification: Notification) {
        adsLoader!.contentComplete()
        self.dismiss(animated: false, completion: nil)
      }

      // MARK: - IMAAdsLoaderDelegate
      func adsLoader(_ loader: IMAAdsLoader!, adsLoadedWith adsLoadedData: IMAAdsLoadedData!) {
        // Grab the instance of the IMAAdsManager and set ourselves as the delegate.
        streamManager = adsLoadedData.streamManager
        streamManager!.delegate = self
        streamManager!.initialize(with: nil)
      }

      func adsLoader(_ loader: IMAAdsLoader!, failedWith adErrorData: IMAAdLoadingErrorData!) {
        print("Error loading ads: \(adErrorData.adError.message ?? "Unknown Error")")
        self.dismiss(animated: false, completion: nil)
      }

      // MARK: - IMAStreamManagerDelegate
      func streamManager(_ streamManager: IMAStreamManager!, didReceive event: IMAAdEvent!) {
        print("StreamManager event \(event.typeString!).")
        //https://developers.google.com/interactive-media-ads/docs/sdks/ios/dai/reference/Enums/IMAAdEventType
        print("Event Case \(event.type.rawValue).")
        switch event.type.rawValue {
        case 17:
          // Log extended data.
          let extendedAdPodInfo = String(format:"Showing ad %zd/%zd, bumper: %@, title: %@, "
            + "description: %@, contentType:%@, pod index: %zd, "
            + "time offset: %lf, max duration: %lf.",
                                         event.ad.adPodInfo.adPosition,
                                         event.ad.adPodInfo.totalAds,
                                         event.ad.adPodInfo.isBumper ? "YES" : "NO",
                                         event.ad.adTitle,
                                         event.ad.adDescription,
                                         event.ad.contentType,
                                         event.ad.adPodInfo.podIndex,
                                         event.ad.adPodInfo.timeOffset,
                                         event.ad.adPodInfo.maxDuration)

          print("\(extendedAdPodInfo)")
          break
        case 3:
          // Prevent user seek through when an ad starts and show the ad controls.
          self.playerViewController!.requiresLinearPlayback = true
          self.adContainerView!.isHidden = false
          break
        case 2:
          // Allow user seek through after an ad ends and hide the ad controls.
          restoreFromSnapback()
          self.playerViewController!.requiresLinearPlayback = false
          self.adContainerView!.isHidden = true
          break
        default:
            print("NO ENTRAMOS")
          break
        }
      }

      func restoreFromSnapback() {
        if userSeekTime > 0.0 {
            let seekCMTime = CMTimeMakeWithSeconds(userSeekTime, 1)
            playerViewController!.player!.seek(to: seekCMTime, toleranceBefore: CMTimeMake(0, 0), toleranceAfter: CMTimeMake(0, 0))
          self.userSeekTime = 0.0
        }
      }

      func streamManager(_ streamManager: IMAStreamManager!, didReceive error: IMAAdError!) {
        print("StreamManager error: \(error.message ?? "Unknown Error")")
        self.dismiss(animated: false, completion: nil)
      }

      // MARK: - AVPlayerViewControllerDelegate
      func playerViewController(
        _ playerViewController: AVPlayerViewController,
        timeToSeekAfterUserNavigatedFrom oldTime: CMTime,
        to targetTime: CMTime
        ) -> CMTime {
        if let streamManager = self.streamManager {
          // perform snapback if user scrubs ahead of ad break
          let targetSeconds = CMTimeGetSeconds(targetTime)
          let prevCuepoint = streamManager.previousCuepoint(forStreamTime: targetSeconds)
          if let cuepoint = prevCuepoint {
            if !cuepoint.isPlayed {
              let oldSeconds = CMTimeGetSeconds(oldTime)
              if oldSeconds < cuepoint.startTime {
                self.userSeekTime = targetSeconds
                return CMTimeMakeWithSeconds(cuepoint.startTime, 1)
              }
            }
          }
        }
        return targetTime
      }

      // MARK: - IMAAVPlayerVideoDisplayDelegate
      func playerVideoDisplay(
        _ playerVideoDisplay: IMAAVPlayerVideoDisplay!,
        didLoad playerItem: AVPlayerItem!
        ) {
        // load bookmark, if it exists (and we aren't playing a live stream)
      }
    }

    class LiveStream: Stream {

        var assetKey:String? = nil

         init(name: String, assetKey: String, apiKey: String? = nil) {
           if let api = apiKey {
             super.init(name: name, apiKey: api)
           } else {
             super.init(name: name)
           }
           self.assetKey = assetKey
         }
    }

    class Stream {
        
        var name:String?    = nil
        var apiKey:String?  = nil

        init(name: String, apiKey: String? = nil) {
          self.name = name
          self.apiKey = apiKey
        }

}
