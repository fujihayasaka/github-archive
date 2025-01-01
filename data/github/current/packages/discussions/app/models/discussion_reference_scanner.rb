# typed: true
# frozen_string_literal: true

# Defines a filter that identifies discussion references inside a string
# Params:
#  - text: the text to be filtered
#  - viewer: the user making the request against whom the permissions for the repository refs are checked
class DiscussionReferenceScanner
  extend T::Sig

  attr_reader :references

  sig { params(text: T.untyped, viewer: T.untyped).void }
  def initialize(text:, viewer:)
    @text = text.strip
    @viewer = viewer

    scan_for_references
  end

  private

  def scan_for_references
    filter = GitHub::HTML::IssueMentionFilter.new("")
    @references = @text.scan(GitHub::HTML::IssueMentionFilter.full_url_discussion_mention)
    @references = @references.filter_map do |matches|
      next unless matches.length >= 2

      nwo = matches.first
      number = matches.second
      reference = filter.discussion_reference(number, nwo)

      next unless reference&.discussion&.readable_by?(@viewer)

      reference.discussion
    end
  end
end
