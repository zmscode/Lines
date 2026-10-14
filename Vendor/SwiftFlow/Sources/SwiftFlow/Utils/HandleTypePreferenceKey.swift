import SwiftUI

/// Preference key for propagating handle types (source/target) through the view hierarchy.
public struct HandleTypePreferenceKey: PreferenceKey {
  public static let defaultValue: [String: HandleType] = [:]

  public static func reduce(
    value: inout [String: HandleType], nextValue: () -> [String: HandleType]
  ) {
    value.merge(nextValue()) { current, _ in current }
  }
}

/// Lines patch: which handles can start a connection drag (`Handle.isConnectable`).
/// Handles that aren't connectable still accept drops.
public struct HandleConnectablePreferenceKey: PreferenceKey {
  public static let defaultValue: [String: Bool] = [:]

  public static func reduce(value: inout [String: Bool], nextValue: () -> [String: Bool]) {
    value.merge(nextValue()) { current, _ in current }
  }
}
