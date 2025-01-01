# typed: strict
# frozen_string_literal: true

class Suggestions::MultiFileDiffComponent < ApplicationComponent
  sig { returns(T::Array[GitHub::Diff::Entry]) }
  attr_reader :diff_entries

  sig { returns(T.nilable(T::Hash[String, T::Array[String]])) }
  attr_reader :file_highlighting

  sig { returns(T.nilable(String)) }
  attr_reader :current_path

  sig { returns(T.nilable(Symbol)) }
  attr_reader :header_type

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :hydro_click_tracking_payload

  sig { returns(T::Boolean) }
  attr_reader :skip_view_patch_menu_item

  VALID_HEADER_TYPES = T.let([:default, :apply_button], T::Array[Symbol])

  sig do
    params(
      diff_entries: T::Array[GitHub::Diff::Entry],
      file_highlighting: T.nilable(T::Hash[String, T::Array[String]]),
      current_path: T.nilable(String),
      header_type: Symbol,
      hydro_click_tracking_payload: T::Hash[Symbol, T.untyped],
      skip_view_patch_menu_item: T::Boolean,
    ).void
  end
  def initialize(diff_entries:, file_highlighting: nil, current_path: nil, header_type: :default, hydro_click_tracking_payload: {}, skip_view_patch_menu_item: false)
    raise ArgumentError, "Invalid header type: #{header_type}, must be one of #{VALID_HEADER_TYPES}" unless VALID_HEADER_TYPES.include?(header_type)

    @diff_entries = diff_entries
    @file_highlighting = file_highlighting
    @current_path = current_path
    @header_type = header_type
    @hydro_click_tracking_payload = hydro_click_tracking_payload
    @skip_view_patch_menu_item = skip_view_patch_menu_item
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
