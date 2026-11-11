# typed: strict
# frozen_string_literal: true

module RuleEngine
  class Violation

    sig { returns(MetadataSources::Types::Candidate) }
    attr_reader :candidate
    sig { returns(T.untyped) }
    attr_reader :metadata

    sig { params(candidate: MetadataSources::Types::Candidate, metadata: T.untyped).void }
    def initialize(candidate:, metadata: nil)
      @candidate = candidate
      @metadata = metadata
    end

    sig { params(result: EvaluationResult).returns(Violation) }
    def self.from_evaluation_result(result)
      new(candidate: result.candidate, metadata: result.metadata)
    end
  end
end
