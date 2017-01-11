//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import ReactiveKit
import Diff

public enum Observable2DArrayChange {
  case reset

  case insertItems([IndexPath])
  case deleteItems([IndexPath])
  case updateItems([IndexPath])
  case moveItem(IndexPath, IndexPath)

  case insertSections(IndexSet)
  case deleteSections(IndexSet)
  case updateSections(IndexSet)
  case moveSection(Int, Int)

  case beginBatchEditing
  case endBatchEditing
}

public protocol Observable2DArrayEventProtocol {
  associatedtype SectionMetadata
  associatedtype Item
  var change: Observable2DArrayChange { get }
  var source: Observable2DArray<SectionMetadata, Item> { get }
}

public struct Observable2DArrayEvent<SectionMetadata, Item> {
  public let change: Observable2DArrayChange
  public let source: Observable2DArray<SectionMetadata, Item>
}

/// Represents a section in 2D array.
/// Section contains its metadata (e.g. header string) and items.
public struct Observable2DArraySection<Metadata, Item> {

  public var metadata: Metadata
  public var items: [Item]

  public init(metadata: Metadata, items: [Item] = []) {
    self.metadata = metadata
    self.items = items
  }
}

public class Observable2DArray<SectionMetadata, Item>: Collection, SignalProtocol {

  public fileprivate(set) var sections: [Observable2DArraySection<SectionMetadata, Item>]
  fileprivate let subject = PublishSubject<Observable2DArrayEvent<SectionMetadata, Item>, NoError>()
  fileprivate let lock = NSRecursiveLock(name: "com.reactivekit.bond.observable2darray")

  public init(_ sections:  [Observable2DArraySection<SectionMetadata, Item>] = []) {
    self.sections = sections
  }

  public var numberOfSections: Int {
    return sections.count
  }

  public func numberOfItems(inSection section: Int) -> Int {
    return sections[section].items.count
  }

  public var startIndex: IndexPath {
    return IndexPath(item: 0, section: 0)
  }

  public var endIndex: IndexPath {
    if numberOfSections == 0 {
      return IndexPath(item: 0, section: 0)
    } else {
      let lastSection = sections[numberOfSections-1]
      return IndexPath(item: lastSection.items.count, section: numberOfSections - 1)
    }
  }

  public func index(after i: IndexPath) -> IndexPath {
    if i.section < sections.count {
      let section = sections[i.section]
      if i.item + 1 < section.items.count {
        return IndexPath(item: i.item + 1, section: i.section)
      } else {
        if i.section + 1 < sections.count {
          return IndexPath(item: 0, section: i.section + 1)
        } else {
          return endIndex
        }
      }
    } else {
      return endIndex
    }
  }

  public var isEmpty: Bool {
    return sections.reduce(true) { $0 && $1.items.isEmpty }
  }

  public var count: Int {
    return sections.reduce(0) { $0 + $1.items.count }
  }

  public subscript(index: IndexPath) -> Item {
    get {
      return sections[index.section].items[index.item]
    }
  }

  public subscript(index: Int) -> Observable2DArraySection<SectionMetadata, Item> {
    get {
      return sections[index]
    }
  }

  public func observe(with observer: @escaping (Event<Observable2DArrayEvent<SectionMetadata, Item>, NoError>) -> Void) -> Disposable {
    observer(.next(Observable2DArrayEvent(change: .reset, source: self)))
    return subject.observe(with: observer)
  }
}

extension Observable2DArray: Deallocatable {

  public var deallocated: Signal<Void, NoError> {
    return subject.disposeBag.deallocated
  }
}

public class MutableObservable2DArray<SectionMetadata, Item>: Observable2DArray<SectionMetadata, Item> {

  /// Append new section at the end of the 2D array.
  public func appendSection(_ section: Observable2DArraySection<SectionMetadata, Item>) {
    lock.lock(); defer { lock.unlock() }
    sections.append(section)
    let sectionIndex = sections.count - 1
    let indices = 0..<section.items.count
    let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
    if indices.count > 0 {
      subject.next(Observable2DArrayEvent(change: .beginBatchEditing, source: self))
      subject.next(Observable2DArrayEvent(change: .insertSections([sectionIndex]), source: self))
      subject.next(Observable2DArrayEvent(change: .insertItems(indexPaths), source: self))
      subject.next(Observable2DArrayEvent(change: .endBatchEditing, source: self))
    } else {
      subject.next(Observable2DArrayEvent(change: .insertSections([sectionIndex]), source: self))
    }
  }

  /// Append `item` to the section `section` of the array.
  public func appendItem(_ item: Item, toSection section: Int) {
    lock.lock(); defer { lock.unlock() }
    sections[section].items.append(item)
    let indexPath = IndexPath(item: sections[section].items.count - 1, section: section)
    subject.next(Observable2DArrayEvent(change: .insertItems([indexPath]), source: self))
  }

  /// Insert section at `index` with `items`.
  public func insert(section: Observable2DArraySection<SectionMetadata, Item>, at index: Int)  {
    lock.lock(); defer { lock.unlock() }
    sections.insert(section, at: index)
    let indices = 0..<section.items.count
    let indexPaths = indices.map { IndexPath(item: $0, section: index) }
    if indices.count > 0 {
      subject.next(Observable2DArrayEvent(change: .beginBatchEditing, source: self))
      subject.next(Observable2DArrayEvent(change: .insertSections([index]), source: self))
      subject.next(Observable2DArrayEvent(change: .insertItems(indexPaths), source: self))
      subject.next(Observable2DArrayEvent(change: .endBatchEditing, source: self))
    } else {
      subject.next(Observable2DArrayEvent(change: .insertSections([index]), source: self))
    }
  }

  /// Insert `item` at `indexPath`.
  public func insert(item: Item, at indexPath: IndexPath)  {
    lock.lock(); defer { lock.unlock() }
    sections[indexPath.section].items.insert(item, at: indexPath.item)
    subject.next(Observable2DArrayEvent(change: .insertItems([indexPath]), source: self))
  }

  /// Insert `items` at index path `indexPath`.
  public func insert(contentsOf items: [Item], at indexPath: IndexPath) {
    lock.lock(); defer { lock.unlock() }
    sections[indexPath.section].items.insert(contentsOf: items, at: indexPath.item)
    let indices = indexPath.item..<indexPath.item+items.count
    let indexPaths = indices.map { IndexPath(item: $0, section: indexPath.section) }
    subject.next(Observable2DArrayEvent(change: .insertItems(indexPaths), source: self))
  }

  /// Move the section at index `fromIndex` to index `toIndex`.
  public func moveSection(from fromIndex: Int, to toIndex: Int) {
    lock.lock(); defer { lock.unlock() }
    let section = sections.remove(at: fromIndex)
    sections.insert(section, at: toIndex)
    subject.next(Observable2DArrayEvent(change: .moveSection(fromIndex, toIndex), source: self))
  }

  /// Move the item at `fromIndexPath` to `toIndexPath`.
  public func moveItem(from fromIndexPath: IndexPath, to toIndexPath: IndexPath) {
    lock.lock(); defer { lock.unlock() }
    let item = sections[fromIndexPath.section].items.remove(at: fromIndexPath.item)
    sections[toIndexPath.section].items.insert(item, at: toIndexPath.item)
    subject.next(Observable2DArrayEvent(change: .moveItem(fromIndexPath, toIndexPath), source: self))
  }

  /// Remove and return the section at `index`.
  @discardableResult
  public func removeSection(at index: Int) -> Observable2DArraySection<SectionMetadata, Item> {
    lock.lock(); defer { lock.unlock() }
    let element = sections.remove(at: index)
    subject.next(Observable2DArrayEvent(change: .deleteSections([index]), source: self))
    return element
  }

  /// Remove and return the item at `indexPath`.
  @discardableResult
  public func removeItem(at indexPath: IndexPath) -> Item {
    lock.lock(); defer { lock.unlock() }
    let element = sections[indexPath.section].items.remove(at: indexPath.item)
    subject.next(Observable2DArrayEvent(change: .deleteItems([indexPath]), source: self))
    return element
  }

  /// Remove all items from the array. Keep empty sections.
  public func removeAllItems() {
    lock.lock(); defer { lock.unlock() }
    let indexPaths = sections.enumerated().reduce([]) { (indexPaths, section) -> [IndexPath] in
      indexPaths + section.element.items.indices.map { IndexPath(item: $0, section: section.offset) }
    }

    for index in sections.indices {
      sections[index].items.removeAll()
    }

    subject.next(Observable2DArrayEvent(change: .deleteItems(indexPaths), source: self))
  }

  /// Remove all items and sections from the array.
  public func removeAllItemsAndSections() {
    lock.lock(); defer { lock.unlock() }
    let indices = sections.indices
    sections.removeAll()
    subject.next(Observable2DArrayEvent(change: .deleteSections(IndexSet(integersIn: indices)), source: self))
  }

  public override subscript(index: IndexPath) -> Item {
    get {
      return sections[index.section].items[index.item]
    }
    set {
      lock.lock(); defer { lock.unlock() }
      sections[index.section].items[index.item] = newValue
      subject.next(Observable2DArrayEvent(change: .updateItems([index]), source: self))
    }
  }

  /// Perform batched updates on the array.
  public func batchUpdate(_ update: (MutableObservable2DArray<SectionMetadata, Item>) -> Void) {
    lock.lock(); defer { lock.unlock() }
    subject.next(Observable2DArrayEvent(change: .beginBatchEditing, source: self))
    update(self)
    subject.next(Observable2DArrayEvent(change: .endBatchEditing, source: self))
  }

  /// Change the underlying value withouth notifying the observers.
  public func silentUpdate(_ update: (inout [Observable2DArraySection<SectionMetadata, Item>]) -> Void) {
    lock.lock(); defer { lock.unlock() }
    update(&sections)
  }
}

extension MutableObservable2DArray: BindableProtocol {

  public func bind(signal: Signal<Observable2DArrayEvent<SectionMetadata, Item>, NoError>) -> Disposable {
    return signal
      .take(until: deallocated)
      .observeNext { [weak self] event in
        guard let s = self else { return }
        s.sections = event.source.sections
        s.subject.next(Observable2DArrayEvent(change: event.change, source: s))
    }
  }
}

// MARK: DataSourceProtocol conformation

extension Observable2DArrayEvent: DataSourceEventProtocol {

  public var kind: DataSourceEventKind {
    switch change {
    case .reset:
      return .reload
    case .insertItems(let indexPaths):
      return .insertItems(indexPaths)
    case .deleteItems(let indexPaths):
      return .deleteItems(indexPaths)
    case .updateItems(let indexPaths):
      return .reloadItems(indexPaths)
    case .moveItem(let from, let to):
      return .moveItem(from, to)
    case .insertSections(let indices):
      return .insertSections(indices)
    case .deleteSections(let indices):
      return .deleteSections(indices)
    case .updateSections(let indices):
      return .reloadSections(indices)
    case .moveSection(let from, let to):
      return .moveSection(from, to)
    case .beginBatchEditing:
      return .beginUpdates
    case .endBatchEditing:
      return .endUpdates
    }
  }

  public var dataSource: Observable2DArray<SectionMetadata, Item> {
    return source
  }
}

extension Observable2DArray: DataSourceProtocol {
}

extension MutableObservable2DArray {
  
  /// Replace section at given index with given section and notify observers to reload section completely
  public func replaceSection(at index: Int, with section: Observable2DArraySection<SectionMetadata, Item>)  {
    lock.lock(); defer { lock.unlock() }
    sections[index] = section
    subject.next(Observable2DArrayEvent(change: .updateSections([index]), source: self))
  }
  
  /// Replace the entier 2d array with a new one forcing a reload
  public func replace2D(with list: Observable2DArray<SectionMetadata, Item>)  {
    lock.lock(); defer { lock.unlock() }
    sections = list.sections
    subject.next(Observable2DArrayEvent(change: .reset, source: self))
  }
  
}

extension MutableObservable2DArray where Item: Equatable {
  
  /// Replace section at given index with given section performing diff if performDiff is true
  /// on all items in section and notifying observers about delets and inserts
  public func replaceSection(at index: Int, with section: Observable2DArraySection<SectionMetadata, Item>, performDiff: Bool) {
    if performDiff {
      lock.lock()
      let diff = sections[index].items.extendedDiff(section.items)
      let patch = diff.patch(from: sections[index].items, to: section.items)

      subject.next(Observable2DArrayEvent(change: .beginBatchEditing, source: self))
      sections[index].metadata = section.metadata
      sections[index].items = section.items

      for step in patch {
        switch step {
        case .insertion(let patchIndex, _):
          let indexPath = IndexPath(item: patchIndex, section: index)
          subject.next(Observable2DArrayEvent(change: .insertItems([indexPath]), source: self))

        case .deletion(let patchIndex):
          let indexPath = IndexPath(item: patchIndex, section: index)
          subject.next(Observable2DArrayEvent(change: .deleteItems([indexPath]), source: self))

        case .move(let from, let to):
          let fromIndexPath = IndexPath(item: from, section: index)
          let toIndexPath = IndexPath(item: to, section: index)

          subject.next(Observable2DArrayEvent(change: .moveItem(fromIndexPath, toIndexPath), source: self))
          
        }
      }

      subject.next(Observable2DArrayEvent(change: .endBatchEditing, source: self))
      lock.unlock()
    } else {
      replaceSection(at: index, with: section)
    }
  }
  
  /// Replace all items in section at given index with given items performing diff between
  /// existing and new items if performDiff is true, otherwise reload section with new items
  public func replaceSection(at index: Int, with items: [Item], performDiff: Bool) {
    replaceSection(at: index, with: Observable2DArraySection<SectionMetadata, Item>(metadata: sections[index].metadata, items: items), performDiff: performDiff)
  }
}

extension MutableObservable2DArray where Item: Equatable, SectionMetadata: Equatable {
  
  // Replace the entire 2DArray performing diff [if given] on all sections and section's items
  // resulting in a series of ordered events (deleteSection, deleteItems, insertSections, insertItems) that migrate the old 2DArray to the new 2DArray
  // Note that both Item and SectionMetadata should be Equatable
  public func replace2D(with list: Observable2DArray<SectionMetadata, Item>, performDiff: Bool) {
    
    if performDiff {
      lock.lock()
      
      // gather old section's metada and new section's metadata
      let oldSectionsMeta = sections.map({$0.metadata})
      let newSectionsMeta = list.sections.map({$0.metadata})
      
      // perform diff on metadata to figure out inserted sections and deleted sections
      let metaDiff = oldSectionsMeta.extendedDiff(newSectionsMeta)
      let metaPatch = metaDiff.patch(from: newSectionsMeta, to: newSectionsMeta)
      
      //let metaDiff = Array.diff(oldSectionsMeta, newSectionsMeta)
      
      var sectionDeletes: [Int] = []
      var sectionInserts: [Int] = []
      var sectionMoves: [(from: Int, to: Int)] = []
      sectionDeletes.reserveCapacity(metaPatch.count)
      sectionInserts.reserveCapacity(metaPatch.count)
      sectionMoves.reserveCapacity(metaPatch.count)
      
      for diffStep in metaPatch {
        switch diffStep {
        case .insertion(let index, _):
          sectionInserts.append(index)
        case .deletion(let index):
          sectionDeletes.append(index)
        case .move(let from, let to):
          sectionMoves.append((from,to))
          //subject.next(ObservableArrayEvent(change: .move(from, to), source: self))
        }
      }
      
      // get sections that stayed there a.k.a neither deleted nor inserted
      var sectionsSame: [(new: Int, old: Int)] = []
      for (i, entry) in newSectionsMeta.enumerated() {
        if let oldIndex = oldSectionsMeta.index(of: entry) {
          sectionsSame.append((new: i, old: oldIndex))
          
        }
      }
      
      var deletesIndexPaths: [IndexPath] = []
      var insertsIndexPaths: [IndexPath] = []
      var movesIndexPaths: [(from: IndexPath, to: IndexPath)] = []
      
      // perform diff on sectionsSame items to get indecies that where deleted, inserted and moved inside those sections
      for entry in sectionsSame {
        
        // the diff should happen between old section's items and new section's items on their corresponding indecies
        let diff = sections[entry.old].items.extendedDiff(list[entry.new].items)
        let patch = diff.patch(from: sections[entry.old].items, to: list[entry.new].items)

        //let diff = Array.diff(sections[entry.old].items, list[entry.new].items)
        
        var deletes: [Int] = []
        var inserts: [Int] = []
        deletes.reserveCapacity(diff.count)
        inserts.reserveCapacity(diff.count)

        
        for diffStep in patch {
          switch diffStep {
          case .insertion(let index, _):
            inserts.append(index)
          case .deletion(let index):
            deletes.append(index)
          case .move(let from, let to):
            movesIndexPaths.append((IndexPath(item: from, section: entry.new), IndexPath(item: to, section: entry.new)))
          }
        }
        
        // deletes should always happen from the old section's place
        deletesIndexPaths.append(contentsOf: deletes.map { IndexPath(item: $0, section: entry.old) })
        
        // insertions should alwyas happen to the new section's place
        insertsIndexPaths.append(contentsOf: inserts.map { IndexPath(item: $0, section: entry.new) })
        
      }
      
      
      subject.next(Observable2DArrayEvent(change: .beginBatchEditing, source: self))
      sections = list.sections
      subject.next(Observable2DArrayEvent(change: .deleteSections(IndexSet(sectionDeletes)), source: self))
      subject.next(Observable2DArrayEvent(change: .deleteItems(deletesIndexPaths), source: self))
      
      for entry in sectionMoves {
        subject.next(Observable2DArrayEvent(change: .moveSection(entry.from, entry.to), source: self))
      }
      
      for entry in movesIndexPaths {
        subject.next(Observable2DArrayEvent(change: .moveItem(entry.from, entry.to), source: self))
      }
      
      
      subject.next(Observable2DArrayEvent(change: .insertSections(IndexSet(sectionInserts)), source: self))
      subject.next(Observable2DArrayEvent(change: .insertItems(insertsIndexPaths), source: self))
      subject.next(Observable2DArrayEvent(change: .endBatchEditing, source: self))
      lock.unlock()
    } else {
      replace2D(with: list)
    }
  }
  
}


