# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::DuplicationIdentifiers
  class Result
    sig { returns(T.untyped) }
    attr_reader :duplicates

    sig { returns(Integer) }
    attr_reader :pull_request_id

    sig { returns(String) }
    attr_reader :identifier_slug

    sig { params(identifier_slug: String, pull_request_id: Integer, duplicates: T.untyped).void }
    def initialize(identifier_slug:, pull_request_id:, duplicates:)
      @identifier_slug = identifier_slug
      @pull_request_id = pull_request_id
      @duplicates = duplicates
    end

    sig { returns(T::Boolean) }
    def duplication_found?
      duplicates.any?(&:present?)
    end
  end
end
