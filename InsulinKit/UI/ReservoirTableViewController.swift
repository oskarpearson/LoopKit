//
//  ReservoirTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopKit

private let ReuseIdentifier = "Reservoir"


public class ReservoirTableViewController: UITableViewController {

    @IBOutlet var needsConfigurationMessageView: ErrorBackgroundView!

    @IBOutlet weak var IOBValueLabel: UILabel!

    @IBOutlet weak var IOBDateLabel: UILabel!

    @IBOutlet weak var totalValueLabel: UILabel!

    @IBOutlet weak var totalDateLabel: UILabel!

    public var doseStore: DoseStore? {
        didSet {
            if let doseStore = doseStore {
                doseStoreObserver = NSNotificationCenter.defaultCenter().addObserverForName(nil, object: doseStore, queue: NSOperationQueue.mainQueue(), usingBlock: { [weak self] (note) -> Void in

                    switch note.name {
                    case DoseStore.ReservoirValuesDidChangeNotification:
                        if self?.isViewLoaded() == true {
                            self?.reloadData()
                        }
                    case DoseStore.ReadyStateDidChangeNotification:
                        switch doseStore.readyState {
                        case .Ready:
                            self?.state = .Display
                        case .Failed(let error):
                            self?.state = .Unavailable(error)
                        default:
                            self?.state = .Unavailable(nil)
                        }
                    default:
                        break
                    }
                })
            } else {
                doseStoreObserver = nil
            }
        }
    }

    private var updateTimer: NSTimer? {
        willSet {
            if let timer = updateTimer {
                timer.invalidate()
            }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        switch doseStore?.readyState {
        case .Ready?:
            state = .Display
        case .Failed(let error)?:
            state = .Unavailable(error)
        default:
            state = .Unavailable(nil)
        }
    }

    public override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        updateTimelyStats(nil)
    }

    public override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)

        let updateInterval = NSTimeInterval(minutes: 5)
        let timer = NSTimer(
            fireDate: NSDate().dateCeiledToTimeInterval(updateInterval).dateByAddingTimeInterval(2),
            interval: updateInterval,
            target: self,
            selector: "updateTimelyStats:",
            userInfo: nil,
            repeats: true
        )
        updateTimer = timer

        NSRunLoop.currentRunLoop().addTimer(timer, forMode: NSDefaultRunLoopMode)
    }

    public override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)

        updateTimer = nil
    }

    public override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)

        if tableView.editing {
            tableView.endEditing(true)
        }
    }

    deinit {
        doseStoreObserver = nil
    }

    // MARK: - Data

    private var reservoirValues: [ReservoirValue] = []

    private enum State {
        case Unknown
        case Unavailable(ErrorType?)
        case Display
    }

    private var state = State.Unknown {
        didSet {
            if isViewLoaded() {
                reloadData()
            }
        }
    }

    private func reloadData() {
        switch state {
        case .Unknown:
            break
        case .Unavailable(let error):
            self.tableView.tableHeaderView?.hidden = true
            self.tableView.tableFooterView = UIView()
            tableView.backgroundView = needsConfigurationMessageView

            if let error = error {
                needsConfigurationMessageView.errorDescriptionLabel.text = String(error)
            } else {
                needsConfigurationMessageView.errorDescriptionLabel.text = nil
            }
        case .Display:
            self.tableView.backgroundView = nil
            self.tableView.tableHeaderView?.hidden = false
            self.tableView.tableFooterView = nil

            doseStore?.getRecentReservoirValues({ [unowned self] (reservoirValues, error) -> Void in
                dispatch_async(dispatch_get_main_queue()) { () -> Void in
                    if error != nil {
                        self.state = .Unavailable(error)
                    } else {
                        self.reservoirValues = reservoirValues

                        if reservoirValues.count > 0 {
                            self.navigationItem.rightBarButtonItem = self.editButtonItem()
                        }

                        self.tableView.reloadData()
                    }
                }

                self.updateTimelyStats(nil)
                self.updateTotal()
            })
        }
    }

    func updateTimelyStats(_: NSTimer?) {
        updateIOB()
    }

    private lazy var IOBNumberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()

        formatter.numberStyle = .DecimalStyle
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    private func updateIOB() {
        if case .Display = state {
            doseStore?.insulinOnBoardAtDate(NSDate()) { (iob, error) -> Void in
                dispatch_async(dispatch_get_main_queue()) {
                    if error != nil {
                        self.state = .Unavailable(error)
                    } else if let value = iob {
                        self.IOBValueLabel.text = self.IOBNumberFormatter.stringFromNumber(value.value)
                        self.IOBDateLabel.text = String(format: NSLocalizedString("com.loudnate.InsulinKit.IOBDateLabel", tableName: "InsulinKit", value: "at %1$@", comment: "The format string describing the date of an IOB value. The first format argument is the localized date."), NSDateFormatter.localizedStringFromDate(value.startDate, dateStyle: .NoStyle, timeStyle: .ShortStyle))
                    } else {
                        self.IOBValueLabel.text = NSNumberFormatter.localizedStringFromNumber(0, numberStyle: .NoStyle)
                        self.IOBDateLabel.text = nil
                    }
                }
            }
        }
    }

    private func updateTotal() {
        if case .Display = state {
            doseStore?.getTotalRecentUnitsDelivered { (total, error) -> Void in
                dispatch_async(dispatch_get_main_queue()) {
                    if error != nil {
                        self.state = .Unavailable(error)
                    } else {
                        self.totalValueLabel.text = NSNumberFormatter.localizedStringFromNumber(total, numberStyle: .NoStyle)

                        if let sinceDate = self.reservoirValues.last?.startDate {
                            self.totalDateLabel.text = String(format: NSLocalizedString("com.loudnate.InsulinKit.totalDateLabel", tableName: "InsulinKit", value: "since %1$@", comment: "The format string describing the starting date of a total value. The first format argument is the localized date."), NSDateFormatter.localizedStringFromDate(sinceDate, dateStyle: .NoStyle, timeStyle: .ShortStyle))
                        } else {
                            self.totalDateLabel.text = nil
                        }
                    }
                }
            }
        }
    }

    private var doseStoreObserver: AnyObject? {
        willSet {
            if let observer = doseStoreObserver {
                NSNotificationCenter.defaultCenter().removeObserver(observer)
            }
        }
    }

    // MARK: - Table view data source

    public override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        switch state {
        case .Unknown, .Unavailable:
            return 0
        case .Display:
            return 1
        }
    }

    public override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reservoirValues.count
    }

    public override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier(ReuseIdentifier, forIndexPath: indexPath)

        if case .Display = state {
            let entry = reservoirValues[indexPath.row]
            let volume = NSNumberFormatter.localizedStringFromNumber(entry.unitVolume, numberStyle: .DecimalStyle)
            let time = NSDateFormatter.localizedStringFromDate(entry.startDate, dateStyle: .NoStyle, timeStyle: .MediumStyle)

            cell.textLabel?.text = "\(volume) U"
            cell.detailTextLabel?.text = time
        }

        return cell
    }

    public override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        return true
    }

    public override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete, case .Display = state {

            let value = reservoirValues.removeAtIndex(indexPath.row)

            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)

            doseStore?.deleteReservoirValue(value) { (_, error) -> Void in
                if let error = error {
                    self.presentAlertControllerWithError(error)
                    self.reloadData()
                }
            }
        }
    }

}
