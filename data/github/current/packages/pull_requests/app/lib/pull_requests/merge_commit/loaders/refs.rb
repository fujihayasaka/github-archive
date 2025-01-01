# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Batch load Refs by Repository.
    module Loaders
      class Refs
        extend T::Sig
        include GitHub::Memoizer

        sig { void }
        def initialize
          @collection = T.let(Hash.new { |hash, key| hash[key] = {} }, T::Hash[Repository, T::Hash[String, T.nilable(String)]])
        end

        # Add a refname to the batch to be loaded.
        sig { params(repo: Repository, refname: T.nilable(String)).void }
        def request(repo, refname)
          return if refname.nil? || refname.blank?

          if hash = @collection[repo]
            hash[refname] = nil
          end
        end

        # Execute the batch and read from the results.
        sig { params(repo: Repository, refname: T.nilable(String)).returns(T.nilable(String)) }
        def read(repo, refname)
          return if refname.nil? || refname.blank?

          execute

          @collection.dig(repo, refname)
        end

        sig { void }
        memoize def execute
          @collection.each do |repo, ref_hash|
            attempts = 0

            # Find all refnames that have not been loaded.
            refnames = ref_hash.filter_map { |key, value| key if value.blank? }

            # Don't execute an empty request.
            next if refnames.blank?

            refs = begin
              attempts += 1

              T.let(
                Array.wrap(Git::Ref::Loader.new(repo).qualified_refs(refnames)).compact,
                T::Array[Git::Ref],
              )
            rescue StandardError => exception # rubocop:disable Lint/GenericRescue
              case GitSystems.classify_exception(exception)
              when GitSystems::Errors::Timeout, GitSystems::Errors::Outage
                if attempts < 3
                  sleep(attempts) unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
                  retry
                end
              end

              # This should halt as we need to know ref state in order to process merge commit requests.
              raise
            end

            # Extract the OID associated with the current state of the loaded refs.
            refs.each { |ref| ref_hash[ref.qualified_name] = ref.sha }
          end
        end
      end
    end
  end
end
