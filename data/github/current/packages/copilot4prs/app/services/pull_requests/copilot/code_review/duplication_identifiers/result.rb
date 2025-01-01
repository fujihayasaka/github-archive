# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::DuplicationIdentifiers
  class Result
    sig { returns(T.untyped) }
    attr_reader :duplicates

    sig { returns(String) }
    attr_reader :identifier_slug

    sig { params(identifier_slug: String, duplicates: T.untyped).void }
    def initialize(identifier_slug:, duplicates:)
      @identifier_slug = identifier_slug
      @duplicates = duplicates
    end

    sig { returns(T::Boolean) }
    def duplication_found?
      duplicates.any?(&:present?)
    end
  end
end
