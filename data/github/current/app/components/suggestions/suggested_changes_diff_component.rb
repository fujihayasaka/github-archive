# typed: true
# frozen_string_literal: true

# This class is used to build out the necessary diff bits to use UnifiedDiffComponent
# when we only have the suggested changes (additions + deletions) from something like a
# markdown PR suggestion (vs a full diff format). We construct just enough of a
# GitHub::Diff::Entry object to be able to use it with the other shared pieces nicely.
class Suggestions::SuggestedChangesDiffComponent < ApplicationComponent
  attr_reader :index, :hydro_click_tracking_payload, :path

  sig do
    params(
      index: Integer,
      path: String,
      raw_additions: T::Array[String],
      raw_deletions: T::Array[String],
      start_line_number: Integer,
      hydro_click_tracking_payload: T::Hash[Symbol, T.untyped],
    ).void
  end
  def initialize(index:, path:, raw_additions:, raw_deletions:, start_line_number:, hydro_click_tracking_payload: {})
    @index = index
    @path = path
    @raw_additions = raw_additions
    @raw_deletions = raw_deletions
    @start_line_number = start_line_number
    @hydro_click_tracking_payload = hydro_click_tracking_payload
  end

  sig { returns(GitHub::Diff::Entry) }
  def diff_entry
    entry = GitHub::Diff::Entry.new(path, path)
    entry.lines << "@@ -#{@start_line_number},#{@raw_deletions.length} +#{@start_line_number},#{@raw_additions.length} @@"

    @raw_deletions.each do |deletion|
      entry.lines << "-#{deletion}"
    end
    @raw_additions.each do |addition|
      entry.lines << "+#{addition}"
    end

    entry.deletions = @raw_deletions.length
    entry.additions = @raw_additions.length
    entry.extended_header_text = ""
    entry
  end

  sig { returns(T.nilable(T::Array[String])) }
  def file_highlighting
    DiffEntryHighlighting.new(diff_entry).highlight_lines
  end
end
