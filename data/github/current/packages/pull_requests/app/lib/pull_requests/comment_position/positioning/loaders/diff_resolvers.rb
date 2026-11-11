# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Loaders
        # Manages DiffResolver instances keyed by commit range, enabling batch resolution
        # of multiple locations across different commit ranges in a single load cycle.
        class DiffResolvers
          sig { params(diff_loader: Positioner::Loaders::Diffs).void }
          def initialize(diff_loader:)
            @diff_loader = diff_loader
            @resolvers = T.let({}, T::Hash[Types::CommitRange, DiffResolver])
          end

          sig { params(location: Types::UnresolvedLocation, range: Types::CommitRange).void }
          def add_to_diff_batch(location, range:)
            find_or_create_resolver(range).add_to_diff_batch(location)
          end

          sig { void }
          def load_diffs!
            @resolvers.each_value(&:load_diffs!)
          end

          sig { params(location: Types::UnresolvedLocation, range: Types::CommitRange).returns(Results::Diff) }
          def fetch(location, range:)
            if resolver = @resolvers[range]
              resolver.fetch(location)
            else
              Results::Diff.failure(outcome: Enums::Outcome::DiffNotLoaded)
            end
          end

          sig { params(path: String, range: Types::CommitRange).returns(T::Boolean) }
          def path_in_diff?(path:, range:)
            if resolver = @resolvers[range]
              resolver.path_in_diff?(path:)
            else
              false
            end
          end

          private

          sig { params(range: Types::CommitRange).returns(DiffResolver) }
          def find_or_create_resolver(range)
            base_commit_oid, head_commit_oid = range

            @resolvers[range] ||= DiffResolver.new(
              diff_loader: @diff_loader,
              base_commit_oid:,
              head_commit_oid:,
            )
          end
        end
      end
    end
  end
end
