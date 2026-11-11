# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Results
        include Enumerable

        extend T::Generic
        Elem = type_member(:out) { { fixed: Result } }

        sig { returns(Results) }
        def self.empty = new([])

        sig { params(results: T::Array[Result]).void }
        def initialize(results)
          @results = results
        end

        sig { override.params(blk: T.proc.params(arg0: Elem).void).void }
        def each(&blk) = @results.each(&blk)

        sig { params(index: Integer).returns(T.nilable(Elem)) }
        def [](index) = @results[index]

        sig { returns(T.nilable(Elem)) }
        def last = @results.last

        sig { returns(T::Boolean) }
        def empty? = @results.empty?

        sig { returns(Result::Outcome) }
        def outcome = @results.last&.outcome || Result::Outcome::Error
      end
    end
  end
end
