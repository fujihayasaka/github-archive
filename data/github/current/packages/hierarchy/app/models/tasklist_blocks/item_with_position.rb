# typed: true
# frozen_string_literal: true

module TasklistBlocks
  class ItemWithPosition
    attr_reader :text
    attr_reader :reference
    attr_reader :position

    sig do
      params(
        text: String,
        position: [Integer, Integer],
      ).void
    end
    def initialize(text:, position:)
      @text = text
      @reference = GitHub::IssueReferenceParser.parse_reference(text)
      @position = position
    end

    def is_reference?
      reference.nil?
    end

    sig do
      params(issue: ::Issue).returns(T::Boolean)
    end
    def does_match_issue?(issue)
      return false if reference.nil?
      reference[:number] == "#{issue.number}" && (reference[:nwo].nil? || reference[:nwo] == issue.repository&.name_with_display_owner)
    end

    sig do
      params(other: ItemWithPosition).returns(T::Boolean)
    end
    def ==(other)
      text == other.text &&
      reference == other.reference &&
      position == other.position
    end
  end
end
