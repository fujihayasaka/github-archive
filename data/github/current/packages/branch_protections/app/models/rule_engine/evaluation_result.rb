# typed: strict
# frozen_string_literal: true

module RuleEngine
  class EvaluationResult

    sig { returns(MetadataSources::Types::Candidate) }
    attr_reader :candidate
    sig { returns(T.untyped) }
    attr_reader :metadata

    sig { params(candidate: MetadataSources::Types::Candidate, success: T::Boolean, metadata: T.untyped).void }
    def initialize(candidate:, success:, metadata: nil)
      @candidate = candidate
      @success = success
      @metadata = metadata
    end

    sig { params(candidate: MetadataSources::Types::Candidate, metadata: T.untyped).returns(EvaluationResult) }
    def self.success(candidate:, metadata: nil)
      new(candidate: candidate, success: true, metadata: metadata)
    end

    sig { params(candidate: MetadataSources::Types::Candidate, metadata: T.untyped).returns(EvaluationResult) }
    def self.failure(candidate:, metadata: nil)
      new(candidate: candidate, success: false, metadata: metadata)
    end

    sig { returns(T::Boolean) }
    def success?
      @success
    end
  end
end
