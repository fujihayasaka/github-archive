# typed: strict
# frozen_string_literal: true

class Suggestions::MultiFileDiffComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T::Array[GitHub::Diff::Entry]) }
  attr_reader :diff_entries

  sig { returns(T.nilable(T::Hash[String, T::Array[String]])) }
  attr_reader :file_highlighting

  sig { returns(T.nilable(String)) }
  attr_reader :current_path

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :hydro_click_tracking_payload

  sig do
    params(
      diff_entries: T::Array[GitHub::Diff::Entry],
      file_highlighting: T.nilable(T::Hash[String, T::Array[String]]),
      current_path: T.nilable(String),
      hydro_click_tracking_payload: T::Hash[Symbol, T.untyped],
    ).void
  end
  def initialize(diff_entries:, file_highlighting: nil, current_path: nil, hydro_click_tracking_payload: {})
    @diff_entries = diff_entries
    @file_highlighting = file_highlighting
    @current_path = current_path
    @hydro_click_tracking_payload = hydro_click_tracking_payload
  end

  # Returns the diff entries so the one matching the current path is first.
  # This is useful when we render this component in relation to a Code Scanning
  # alert associated with a specific file.
  sig { returns(T::Array[GitHub::Diff::Entry]) }
  def ordered_diff_entries
    return diff_entries unless current_path

    current_diff_entry = T.let(nil, T.untyped)
    out = diff_entries.reject do |diff_entry|
      if diff_entry.path == current_path
        current_diff_entry = diff_entry
        true
      else
        false
      end
    end

    out.unshift(current_diff_entry) if current_diff_entry

    out
  end
end
