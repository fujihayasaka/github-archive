# typed: true
# frozen_string_literal: true

module RuleEngine
  class StatusCheckEvaluator
    class Loader
      # Wraps an array of `Status` and `CombinedStatus::CheckRunAdapter`
      # records and provides the standard Ruby Enumerable interface, plus
      # some convenience methods e.g. for filtering the results by commit OID
      # and context.
      class Result
        extend T::Generic
        include Enumerable

        Elem = type_member { { fixed: T.any(Status, CombinedStatus::CheckRunAdapter) } }

        sig { params(checks: T::Array[Elem]).void }
        def initialize(checks)
          @checks = checks
        end

        def each(&block)
          @checks.each(&block)
        end

        sig { params(context: String).returns(Result) }
        def for_context(context)
          filtered_checks = @checks.filter do |check|
            if check.is_a?(Status)
              # Status comparison must be case insensitive to match existing
              # behavior
              check.context.downcase == context.downcase
            else
              check.context == context
            end
          end
          Result.new(filtered_checks)
        end

        sig { params(commit_oids: T::Enumerable[String]).returns(Result) }
        def for_commits(commit_oids)
          commit_oid_set = commit_oids.to_set
          filtered_checks = @checks.filter do |check|
            commit_oid_set.include?(check.commit_oid)
          end
          Result.new(filtered_checks)
        end

        sig { returns(T::Set[String]) }
        def commit_oids
          @checks.map(&:commit_oid).to_set
        end
      end
    end
  end
end
