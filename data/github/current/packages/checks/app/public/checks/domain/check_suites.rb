# typed: strict
# frozen_string_literal: true

module Checks
  class Domain
    class CheckSuites < GH::Domain::Base
      # Get the CheckSuite for the given repository and Head SHA.
      #
      # @param repo The Repository in which to create the check suite.
      # @param head_sha The head SHA to scope to.
      # @param pagination The pagination to apply to the results.
      # @param sorts The sorts to apply to the results.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(repo: Repository, head_sha: String, time: ::ActiveSupport::TimeWithZone, pagination: GH::Pagination::Base, sorts: T.nilable(T::Array[GH::Pagination::Sort])).
        returns(GH::Domain::Collection[CheckSuite]).
        checked(:always).
        on_failure(:raise)
      end
      def for_head_sha_created_before(repo:, head_sha:, time:,  pagination:, sorts: nil)
        check_suites = repo.check_suites.where(head_sha: head_sha).where("created_at <= ?", time)

        GH::Pagination::Paginator.paginate(scope: check_suites, pagination:, sorts:)
      end

      # Prefetch the data for the given properties on the CheckSuite.
      #
      # @param check_suites The CheckSuites to prefetch.
      # @param properties The properties to prefetch.
      # @return The CheckSuites with their data prefetched.
      sig do
        type_parameters(:CollectionType).
        params(check_suites: T.all(T::Enumerable[CheckSuite], T.type_parameter(:CollectionType)), properties: T::Array[Symbol]).
        returns(T.all(T::Enumerable[CheckSuite], T.type_parameter(:CollectionType))).
        checked(:always).
        on_failure(:raise)
      end
      def prefetch(check_suites, properties)
        GitHub::PrefillAssociations.prefill_associations(check_suites, properties)
        check_suites
      end

      # Find or create a check suite for the given repository and head SHA.
      #
      # @param repo The Repository in which to create the check suite.
      # @param head_sha The head SHA to scope to.
      # @param github_app_id The GitHub App ID creating the check suite.
      # @return The existing CheckSuite if it exists, or a new CheckSuite if it does not.
      # rubocop:disable Metrics/MethodLength
      sig do
        params(repo: Repository, head_sha: String, github_app_id: Integer).
        returns(CheckSuite).
        checked(:always).
        on_failure(:raise)
      end
      def find_or_create(repo:, head_sha:, github_app_id:)
        attrs = {
          head_sha: head_sha,
          github_app_id: github_app_id,
        }

        check_suite = repo.check_suites.find_by(attrs)
        return check_suite if check_suite.present?

        # When creating check suites elsewhere in the app, if the push is known we use it to set the
        # head_branch attribute. While we don't accept a head_branch param from integrators in the
        # api, it seems reasonable to use the information we know to better fill in the details.
        push = Repositories.domain.pushes.by_repo_id_and_after(after: head_sha, repository_id: repo.id)

        attrs.merge!(
          head_branch: push&.branch_name,
          push_id: push&.id,
        )

        # Attempts to find the check suite, otherwise tries to create the check suite.
        # If creation fails because the record is not unique, retry up to 3 times.
        retries = 3
        begin
          repo.check_suites.find_by(attrs) || repo.check_suites.create!(attrs)
        rescue ActiveRecord::RecordNotUnique
          GitHub.dogstats.increment("checks.check_suite_uniqueness_collision")
          (retries -= 1) && retry if retries > 0
          raise # Re-raises the same error
        end
      end

      # Get the CheckSuite for the given ID.
      #
      # @param repository_id The Repository ID to scope to.
      # @param id The ID of the CheckSuite to get.
      # @return The CheckSuite for the given ID in the repository.
      sig do
        params(id: Integer, repository_id: Integer).
        returns(T.nilable(CheckSuite)).
        checked(:always).
        on_failure(:raise)
      end
      def for_id(id, repository_id:)
        ActiveRecord::Base.connected_to(role: :reading) do
          CheckSuite.find_by(id: id, repository_id: repository_id)
        end
      end

      # Get the latest check suites for a given repository, optionally excluding check suites for certain GitHub Apps.
      #
      # @param repository_id The Repository ID to scope to.
      # @param github_app_ids_to_exclude The GitHub App IDs to exclude from the results.
      # @param limit The number of check suites to return, defaults to 30 if not provided.
      # @return The CheckSuite for the given ID in the repository.
      sig do
        params(repository_id: Integer, github_app_ids_to_exclude: T::Array[String], limit: Integer).
        returns(T::Array[CheckSuite]).
        checked(:always).
        on_failure(:raise)
      end
      def latest_ids(repository_id, github_app_ids_to_exclude: [], limit: 30)
        ActiveRecord::Base.connected_to(role: :reading) do
          relation = CheckSuite.where(repository_id: repository_id)
            .where(CheckSuite.arel_table[:github_app_id].not_in(github_app_ids_to_exclude))
            .order(id: :desc)
            .limit(limit)

          results = relation.to_a
        end
      end
    end
  end
end
