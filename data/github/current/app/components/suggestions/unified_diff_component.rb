# typed: strict
# frozen_string_literal: true

require "securerandom"

class Suggestions::UnifiedDiffComponent < ApplicationComponent
  renders_one :header_additions

  sig { returns(GitHub::Diff::Entry) }
  attr_reader :diff_entry

  sig { returns(T.nilable(T::Array[String])) }
  attr_reader :file_highlighting

  sig { returns(T::Boolean) }
  attr_reader :not_collapsed

  sig { returns(T::Boolean) }
  attr_reader :skip_view_patch_menu_item

  sig do
    params(
      diff_entry: GitHub::Diff::Entry,
      file_highlighting: T.nilable(T::Array[String]),
      hydro_click_tracking_payload: T::Hash[Symbol, T.untyped],
      not_collapsed: T::Boolean,
      skip_view_patch_menu_item: T::Boolean,
    ).void
  end
  def initialize(diff_entry:, file_highlighting: nil, hydro_click_tracking_payload: {}, not_collapsed: true, skip_view_patch_menu_item: false)
    @diff_entry = diff_entry
    @file_highlighting = file_highlighting
    @hydro_click_tracking_payload = hydro_click_tracking_payload
    @not_collapsed = not_collapsed
    @skip_view_patch_menu_item = skip_view_patch_menu_item
  end

  sig { returns(String) }
  memoize def code_block_id
    "autofix-patch-code-block-#{SecureRandom.hex(16)}"
  end

  sig { returns(String) }
  memoize def copy_paste_patch_dialog_id
    "autofix-patch-dialog-#{SecureRandom.hex(16)}"
  end

  sig { returns(T::Array[T::Hash[Symbol, T.any(Integer, String)]]) }
  def modified_lines
    regions = []
    current_region = T.let(nil, T.nilable({ start: Integer, end: Integer, lines: String }))
    diff_entry.each_line do |line|
      if line.addition?
        if current_region
          current_region[:end] = line.right
          current_region[:lines] << line.text[1..-1] + "\n"
        else
          current_region = {
            start: line.right,
            end: line.right,
            lines: line.text[1..-1] + "\n",
          }
          regions << current_region
        end
      elsif current_region
        current_region = nil
      end
    end
    regions
  end

  # See related `subscribe("browser.code_scanning_autofix.patch_copied")` in config/instrumentation/hydro/subscriptions/code_scanning.rb
  sig { returns(T::Hash[String, String]) }
  memoize def hydro_click_patch_copied_tracking_attributes
    hydro_click_tracking_attributes("code_scanning_autofix.patch_copied", hydro_click_tracking_payload)
  end

  # See related `subscribe("browser.code_scanning_autofix.diff_lines_copied")` in config/instrumentation/hydro/subscriptions/code_scanning.rb
  sig { returns(T::Hash[String, String]) }
  memoize def hydro_click_diff_lines_copied_tracking_attributes
    hydro_click_tracking_attributes("code_scanning_autofix.diff_lines_copied", hydro_click_tracking_payload)
  end

  # This is a simplified version of GitHub::Diff::Entry#to_diff_text to fix the encoding of the diff text.
  sig { returns(String) }
  def diff_text
    "#{diff_entry.header_text}#{diff_entry.extended_header_text}#{diff_entry.unicode_text}\n"
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :hydro_click_tracking_payload
end
