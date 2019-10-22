//
//  DataSourceProvider.swift
//  AccordionSwift
//
//  Created by Victor Sigler Lopez on 7/3/18.
//  Updated by Kyle Wood on 15/10/19.
//  Copyright © 2018 Victor Sigler. All rights reserved.
//

import Foundation
import os.log

// Defines if there can be multiple cells expanded at once
public enum NumberOfExpandedParentCells {
    case single
    case multiple
}

public final class DataSourceProvider<DataSource: DataSourceType,
                                     ParentCellConfig: CellViewConfigType,
                                     ChildCellConfig: CellViewConfigType>
        where ParentCellConfig.Item == DataSource.Item, ChildCellConfig.Item == DataSource.Item.ChildItem {

    // MARK: - Typealias

    public typealias DidSelectParentAtIndexPathClosure = (UITableView, IndexPath, DataSource.Item?) -> Void
    public typealias DidSelectChildAtIndexPathClosure = (UITableView, IndexPath, DataSource.Item.ChildItem?) -> Void

    public typealias HeightForChildAtIndexPathClosure = (UITableView, IndexPath, DataSource.Item.ChildItem?) -> CGFloat
    public typealias HeightForParentAtIndexPathClosure = (UITableView, IndexPath, DataSource.Item?) -> CGFloat

    private typealias ParentCell = (indexPath: IndexPath, index: Int)

    // MARK: - Properties

    /// The data source.
    public var dataSource: DataSource

    // The currently expanded parent
    private var expandedParent: ParentCell? = nil

    // Defines if accordion can have more than one cell open at a time
    private var numberOfExpandedParentCells: NumberOfExpandedParentCells

    /// The parent cell configuration.
    private let parentCellConfig: ParentCellConfig

    /// The child cell configuration.
    private let childCellConfig: ChildCellConfig

    /// The UITableViewDataSource
    private var _tableViewDataSource: TableViewDataSource?

    /// The UITableViewDelegate
    private var _tableViewDelegate: TableViewDelegate?

    /// The closure to be called when a Parent cell is selected
    private let didSelectParentAtIndexPath: DidSelectParentAtIndexPathClosure?

    /// The closure to be called when a Child cell is selected
    private let didSelectChildAtIndexPath: DidSelectChildAtIndexPathClosure?

    /// The closure to define the height of the Parent cell at the specified IndexPath
    private let heightForParentCellAtIndexPath: HeightForParentAtIndexPathClosure?

    /// The closure to define the height of the Child cell at the specified IndexPath
    private let heightForChildCellAtIndexPath: HeightForChildAtIndexPathClosure?

    /// The closure to be called when scrollView is scrolled
    private let scrollViewDidScroll: ScrollViewDidScrollClosure?

    // MARK: - Initialization

    /// Initializes a new data source provider.
    ///
    /// - Parameters:
    ///   - dataSource: The data source.
    ///   - cellConfig: The cell configuration.
    public init(dataSource: DataSource,
                parentCellConfig: ParentCellConfig,
                childCellConfig: ChildCellConfig,
                didSelectParentAtIndexPath: DidSelectParentAtIndexPathClosure? = nil,
                didSelectChildAtIndexPath: DidSelectChildAtIndexPathClosure? = nil,
                heightForParentCellAtIndexPath: HeightForParentAtIndexPathClosure? = nil,
                heightForChildCellAtIndexPath: HeightForChildAtIndexPathClosure? = nil,
                scrollViewDidScroll: ScrollViewDidScrollClosure? = nil,
                numberOfExpandedParentCells: NumberOfExpandedParentCells = .multiple,
                expandParentAtIndex: Int? = nil
    ) {
        self.expandedParent = nil
        self.parentCellConfig = parentCellConfig
        self.childCellConfig = childCellConfig
        self.didSelectParentAtIndexPath = didSelectParentAtIndexPath
        self.didSelectChildAtIndexPath = didSelectChildAtIndexPath
        self.heightForParentCellAtIndexPath = heightForParentCellAtIndexPath
        self.heightForChildCellAtIndexPath = heightForChildCellAtIndexPath
        self.scrollViewDidScroll = scrollViewDidScroll
        self.numberOfExpandedParentCells = numberOfExpandedParentCells

        var mutableDataSource = dataSource
        let numberOfParentCells = mutableDataSource.numberOfParents()

        if numberOfParentCells == 0 {
            os_log("The data source does not contain any parents", type: .error)
            self.dataSource = dataSource
            return
        }

        let hasMultipleParentsExpandedInDataSource = numberOfExpandedParentCells == .single && mutableDataSource.numberOfExpandedParents() > 0
        if hasMultipleParentsExpandedInDataSource {
            os_log("There are expanded parent cells in the data source. Defaulting to collapsing all expanded cells", type: .error)
            mutableDataSource.collapseAll()
        }

        if let index = expandParentAtIndex {
            // If specified expand the parent at index
            var indexToExpand = index
            let indexIsOutOfBounds = index < 0 || index > numberOfParentCells

            if indexIsOutOfBounds {
                os_log("The expandParentAtIndex supplied is out of bounds. Defaulting to expanding the first parent", type: .error)
                indexToExpand = 0
            }

            expandedParent = ParentCell(indexPath: IndexPath(item: indexToExpand, section: 0), index: indexToExpand)
            mutableDataSource.toggleParentCell(toState: .expanded, inSection: 0, atIndex: indexToExpand)
        }

        self.dataSource = mutableDataSource
    }

// MARK: - Private Methods

// Update the cells of the table based on the selected parent cell
//
// - Parameters:
//   - tableView: The UITableView to update
//   - item: The DataSource item that was selected
//   - currentPosition: The current position in the data source
//   - indexPaths: The last IndexPath of the new cells expanded
//   - parentIndex: The index of the parent item selected
    private func update(_ tableView: UITableView, _ item: DataSource.Item?, _ currentPosition: Int, _ indexPath: IndexPath, _ parentIndex: Int) {
        guard let item = item else {
            return
        }

        let numberOfChildren = item.children.count
        guard numberOfChildren > 0 else {
            return
        }

        let selectedParentCell: ParentCell = ParentCell(
                indexPath: indexPath,
                index: parentIndex)

        tableView.beginUpdates()
        toggle(selectedParentCell, withState: item.state, tableView)
        tableView.endUpdates()

        // If the cells were expanded then we verify if they are inside the CGRect
        if item.state == .expanded {
            let lastCellIndexPath = IndexPath(item: indexPath.item + numberOfChildren, section: indexPath.section)
            // Scroll the new cells expanded in case of be outside the UITableView CGRect
            scrollCellIfNeeded(atIndexPath: lastCellIndexPath, tableView)
        }
    }

// Toggle the state of the selected parent cell between expanded and collapsed
//
// - Parameters:
//   - currentState: The current state of the selected parent
//   - selectedParentCell: The actual cell selected
    private func toggle(_ selectedParentCell: ParentCell, withState currentState: State, _ tableView: UITableView) {
        switch (currentState, numberOfExpandedParentCells) {
        case (.expanded, _):
            // Collapse the parent and it's children
            collapse(parent: selectedParentCell, tableView)
            expandedParent = nil
        case (.collapsed, .single):
            // Expand the parent and it's children and collapse the expanded parent
            if let expandedParent = expandedParent {
                collapse(parent: expandedParent, tableView)
            }
            expand(parent: selectedParentCell, tableView)
            expandedParent = selectedParentCell
        case (.collapsed, .multiple):
            // Expand the parent and it's children
            expand(parent: selectedParentCell, tableView)
        }
    }

// Expand the parent cell and it's children
//
// - Parameters:
//   - parent: The actual parent cell to be expanded
    private func expand(parent: ParentCell, _ tableView: UITableView) {
        let numberOfChildren = dataSource.item(atRow: parent.index, inSection: parent.indexPath.section)?.children.count ?? 0

        guard numberOfChildren > 0 else {
            return
        }

        let indexPaths = getIndexes(parent, numberOfChildren)
        tableView.insertRows(at: indexPaths, with: .fade)
        dataSource.toggleParentCell(toState: .expanded, inSection: parent.indexPath.section, atIndex: parent.index)
    }

// Collapse the parent cell and it's children
//
// - Parameters:
//   - parent: The actual parent cell to be expanded
    private func collapse(parent: ParentCell, _ tableView: UITableView) {
        let numberOfChildren = dataSource.item(atRow: parent.index, inSection: parent.indexPath.section)?.children.count ?? 0

        guard numberOfChildren > 0 else {
            return
        }

        let indexPaths = getIndexes(parent, numberOfChildren)
        tableView.deleteRows(at: indexPaths, with: .fade)
        dataSource.toggleParentCell(toState: .collapsed, inSection: parent.indexPath.section, atIndex: parent.index)
    }

///  Get a list of index paths of the children of the parent cell
///
/// - Parameters:
///   - parent: The parent cell
///   - numberOfChildren: The number of children the parent has
    private func getIndexes(_ parent: ParentCell, _ numberOfChildren: Int) -> [IndexPath] {
        let startPosition: Int = {
            switch numberOfExpandedParentCells {
            case .single:
                // Make use of parent index due to fact indexPath.row does not update the row position after
                // collapsing the previously expanded parent
                return parent.index
            case .multiple:
                // Make use of indexPath if multiple parents can be expanded as indexPath.row will be up to date
                return parent.indexPath.row
            }
        }()
        return (1...numberOfChildren).map {
            offset -> IndexPath in
            IndexPath(row: startPosition + offset, section: parent.indexPath.section)
        }
    }

/// Scroll the new cells expanded in case of be outside the UITableView CGRect
///
/// - Parameters:
///   - indexPaths: The last IndexPath of the new cells expanded
///   - tableView: The UITableView to update
    private func scrollCellIfNeeded(atIndexPath indexPath: IndexPath, _ tableView: UITableView) {

        let cellRect = tableView.rectForRow(at: indexPath)

        // Scroll to the cell in case of not being visible
        if !tableView.bounds.contains(cellRect) {
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }

}

extension DataSourceProvider {

    // MARK: - UITableViewDataSource

    /// The UITableViewDataSource protocol handler
    public var tableViewDataSource: UITableViewDataSource {
        if _tableViewDataSource == nil {
            _tableViewDataSource = configTableViewDataSource()
        }

        return _tableViewDataSource!
    }

    /// Config the UITableViewDataSource methods
    ///
    /// - Returns: An instance of the `TableViewDataSource`
    private func configTableViewDataSource() -> TableViewDataSource {

        let dataSource = TableViewDataSource(
                numberOfSections: { [unowned self] () -> Int in
                    return self.dataSource.numberOfSections()
                },
                numberOfItemsInSection: { [unowned self] (section) -> Int in
                    return self.dataSource.numberOfItems(inSection: section)
                })

        dataSource.tableCellForRowAtIndexPath = { [unowned self] (tableView, indexPath) -> UITableViewCell in

            let (parentPosition, isParent, currentPos) = self.dataSource.findParentOfCell(atIndexPath: indexPath)

            guard isParent else {
                let item = self.dataSource.childItem(at: indexPath, parentIndex: parentPosition, currentPos: currentPos)
                return self.childCellConfig.tableCellFor(item: item!, tableView: tableView, indexPath: indexPath)
            }

            let item = self.dataSource.item(at: IndexPath(item: parentPosition, section: indexPath.section))!
            return self.parentCellConfig.tableCellFor(item: item, tableView: tableView, indexPath: indexPath)
        }

        dataSource.tableTitleForHeaderInSection = { [unowned self] (section) -> String? in
            return self.dataSource.headerTitle(inSection: section)
        }

        dataSource.tableTitleForFooterInSection = { [unowned self] (section) -> String? in
            return self.dataSource.footerTitle(inSection: section)
        }

        return dataSource
    }
}

extension DataSourceProvider {

    // MARK: - UITableViewDelegate

    /// The UITableViewDataSource protocol handler
    public var tableViewDelegate: UITableViewDelegate {
        if _tableViewDelegate == nil {
            _tableViewDelegate = configTableViewDelegate()
        }

        return _tableViewDelegate!
    }

    /// Config the UITableViewDelegate methods
    ///
    /// - Returns: An instance of the `TableViewDelegate`
    private func configTableViewDelegate() -> TableViewDelegate {

        let delegate = TableViewDelegate()

        delegate.didSelectRowAtIndexPath = { [unowned self] (tableView, indexPath) -> Void in
            let (parentIndex, isParent, currentPosition) = self.dataSource.findParentOfCell(atIndexPath: indexPath)
            let item = self.dataSource.item(atRow: parentIndex, inSection: indexPath.section)

            if isParent {
                self.update(tableView, item, currentPosition, indexPath, parentIndex)
                self.didSelectParentAtIndexPath?(tableView, indexPath, item)
            } else {
                let index = indexPath.row - currentPosition - 1
                let childItem = index >= 0 ? item?.children[index] : nil
                self.didSelectChildAtIndexPath?(tableView, indexPath, childItem)
            }
        }

        delegate.heightForRowAtIndexPath = { [unowned self] (tableView, indexPath) -> CGFloat in
            let (parentIndex, isParent, currentPosition) = self.dataSource.findParentOfCell(atIndexPath: indexPath)
            let item = self.dataSource.item(atRow: parentIndex, inSection: indexPath.section)

            if isParent {
                return self.heightForParentCellAtIndexPath?(tableView, indexPath, item) ?? 40
            }

            let index = indexPath.row - currentPosition - 1
            let childItem = index >= 0 ? item?.children[index] : nil
            return self.heightForChildCellAtIndexPath?(tableView, indexPath, childItem) ?? 35
        }

        delegate.scrollViewDidScrollClosure = { [unowned self] (scrollView) -> Void in
            self.scrollViewDidScroll?(scrollView)
        }

        return delegate
    }
}

