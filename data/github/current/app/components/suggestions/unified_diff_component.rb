# typed: strict
# frozen_string_literal: true

require "securerandom"

class Suggestions::UnifiedDiffComponent < ApplicationComponent
  extend T::Sig

  sig { returns(GitHub::Diff::Entry) }
  attr_reader :diff_entry

  sig { returns(T.nilable(T::Array[String])) }
  attr_reader :file_highlighting

  sig { returns(T::Boolean) }
  attr_reader :current_path

  sig do
    params(
      diff_entry: GitHub::Diff::Entry,
      file_highlighting: T.nilable(T::Array[String]),
      current_path: T::Boolean,
      hydro_click_tracking_payload: T::Hash[Symbol, T.untyped],
    ).void
  end
  def initialize(diff_entry:, file_highlighting: nil, current_path: true, hydro_click_tracking_payload: {})
    @diff_entry = diff_entry
    @file_highlighting = file_highlighting
    @current_path = current_path
    @hydro_click_tracking_payload = hydro_click_tracking_payload
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

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :hydro_click_tracking_payload
end
