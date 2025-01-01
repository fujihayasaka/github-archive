# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    class BatchReadCommits
      include GitHub::Memoizer

      Collection = T.type_alias { T::Hash[Repository, T::Hash[T.nilable(String), T.nilable(::Commit)]] }

      sig { void }
      def initialize
        @collection = T.let(Hash.new { |hash, key| hash[key] = {} }, Collection)
      end

      # Add a commit to the batch to be loaded.
      sig { params(repo: Repository, oid: T.nilable(String)).void }
      def request(repo, oid)
        return if oid.nil? || oid.blank?

        if hash = @collection[repo]
          hash[oid] = nil
        end
      end

      # Execute the batch and read from the results.
      sig { params(repo: Repository, oid: T.nilable(String)).returns(T.nilable(::Commit)) }
      def read(repo, oid)
        return if oid.nil? || oid.blank?

        execute

        @collection.dig(repo, oid)
      end

      sig { void }
      memoize def execute
        @collection.each do |repo, commits_hash|
          attempts = 0

          # Find all oids that have not been loaded.
          oids = commits_hash.filter_map { |key, value| key if value.blank? }

          # Don't execute an empty request.
          next if oids.blank?

          commits = begin
            attempts += 1

            T.let(
              Array.wrap(repo.objects.read_all(oids.compact, "commit", skip_bad: true)).compact,
              T::Array[::Commit]
            )
          rescue StandardError => exception # rubocop:disable Lint/RescueException
            case GitSystems.classify_exception(exception)
            when GitSystems::Errors::Timeout, GitSystems::Errors::Outage
              if attempts < 3
                sleep(attempts) unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
                retry
              end
            end

            # Treat the commits as not found. There's no guarantees that
            # we will always find a commit.
            next
          end

          # Extract the Commit object with the requested data structure.
          commits.each { |commit| commits_hash[commit.oid] = commit }
        end
      end
    end
  end
end
