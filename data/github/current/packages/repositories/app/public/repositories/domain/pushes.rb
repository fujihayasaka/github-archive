# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Pushes < GH::Domain::Base
      extend T::Sig

      # Fetches pushes for given repository and pusher newer than specified pushed_at date.
      # Supposed to hit `index_pushes_on_repository_id_and_pusher_id_and_pushed_at` index.
      #
      # Serves data for `recently_touched_branches_for` method,
      # that gets the repository's three branches whose heads were most recently touched by the specified user.
      # pushed_at param is always set to 1.hour.ago
      sig { params(repository: ::Repository, pusher: ::User, pushed_at: Time).returns(GH::Domain::Collection[Repositories::IPush]).checked(:always).on_failure(:raise) }
      def latest_for(repository:, pusher:, pushed_at:)
        results = ::Push
          .where(repository: repository, pusher: pusher, pushed_at: pushed_at..)
          .order(pushed_at: :desc)
          .to_a

        GH::Domain::Collection.new(results)
      end

      # Checks if a push exists for given repository, pusher, and ref newer than specified pushed_at date.
      #
      # Serves data for `pushed_to_head_since_open?` method,
      # that evaluates whether a given user has pushed to a given PR's branch after the PR was opened.
      # Pushing to the branch after a pull request is opened will disqualify users from being eligible to approve it.
      #
      # pushed_at param is set to PR's creation time.
      # In theory a PR could be very old, and then we have to fetch many old pushes, but that's more of an edge case?
      # Either way, filtering by PR's ref already reduces very much the iterated set.
      #
      # Supposed to hit `index_pushes_on_repository_id_and_pusher_id_and_pushed_at` index or
      # `index_pushes_on_repository_id_and_ref_and_pushed_at`
      # "refs/heads/" will be prepended to ref in order to match the expected format of the ref column in the pushes table
      sig { params(repository_id: ::Integer, ref: ::String, pusher: ::User, pushed_at: Time).returns(T::Boolean).checked(:always).on_failure(:raise) }
      def exists_for_ref(repository_id:, ref:, pusher:, pushed_at:)
        ::Push
          .where(repository_id: repository_id, ref: "refs/heads/#{ref}", pusher: pusher, pushed_at: pushed_at..)
          .exists?
      end

      # Fetches pushes for given repository newer than specified pushed_at date.
      #
      # Serves data for `recently_touched_branches` method from `repository_advisory`,
      # that gets the repository's child repository (aka workspace repository) used for preparing advisory fixes,
      # and fetches recently touched branches, and suggest to create a new PRs from them.
      # Such repositories are normally short-living and have very limited amount of pushes.
      # pushed_at param is always set to 24.hours.ago
      #
      # Supposed to PARTIALLY hit `index_pushes_on_repository_id_and_ref_and_pushed_at` index.
      # NOTE: Once we add `index_pushes_on_repository_id_and_pushed_at` - it will hit it.
      sig { params(repository: ::Repository, pushed_at: Time, limit: T.nilable(Integer)).returns(GH::Domain::Collection[Repositories::IPush]).checked(:always).on_failure(:raise) }
      def latest(repository:, pushed_at:, limit: nil)
        results = ::Push
          .where(repository: repository, pushed_at: pushed_at..)
          .limit(limit)
          .order(pushed_at: :desc)
          .to_a

        GH::Domain::Collection.new(results)
      end

      # Fetches the last push for a given repository
      # Returns nil if no matching record is found
      #
      # Serves data for `test_webhook` method from `webhook_dependency`,
      # and at the same time used in many tests as a helper method,
      # to fetch a push for a corresponding pull_request/notification/check_suite/etc.
      sig { params(repository_id: Integer).returns(T.nilable(Repositories::IPush)).checked(:always).on_failure(:raise) }
      def latest_for_repo(repository_id:)
        ::Push
          .where(repository_id: repository_id)
          .order(pushed_at: :desc)
          .first
      end

      # TODO: Delete when FF `ref_push_reactive_cleanup_sha` is removed
      # Fetches the last push for a given repository and ref
      # Returns nil if no matching record is found
      sig { params(repository_id: Integer, ref: String).returns(T.nilable(Repositories::IPush)).checked(:always).on_failure(:raise) }
      def latest_for_ref(repository_id:, ref:)
        ::Push
          .where(repository_id:, ref:)
          .order(pushed_at: :desc)
          .first
      end

      # Fetches the earliest `before` SHA entry in the `pushes` table for a given repository,
      # ref, pusher, and specified `after` SHA. Returns nil if none found.
      # This can be used to find the earliest before SHA for a merge.
      sig { params(repository_id: Integer, ref: String, pusher_id: Integer, after: String).returns(T.nilable(String)).checked(:always).on_failure(:raise) }
      def first_before_sha_for(repository_id:, ref:, pusher_id:, after:)
        ::Push.where(repository_id: repository_id, ref: ref, pusher_id: pusher_id, after: after)
          .order(id: :asc)
          .limit(1)
          .pluck(:before)
          .first
      end

      # Public: Fetch pushes for the given repository and given ids.
      #
      # Options:
      # - repository - The repository to fetch the pushes for.
      #
      # Returns an array of Pushes sorted in descending id order.
      sig { params(push_ids: T::Array[Integer], repository: ::Repository).returns(GH::Domain::Collection[Repositories::IPush]).checked(:always).on_failure(:raise) }
      def load_pushes_for_repository(push_ids:, repository:)
        results = ::Push.where(repository: repository, id: push_ids).order(id: :desc).to_a
        GH::Domain::Collection.new(results)
      end

      # Public: Fetch pushes for the given repository_id and given ids.
      #
      # Options:
      # - push_ids - The ids of the pushes to fetch.
      # - repository_id - The repository to fetch the pushes for.
      #
      # Returns an array of Pushes
      sig { params(push_ids: T::Array[Integer], repository_id: Integer).returns(GH::Domain::Collection[Repositories::IPush]).checked(:always).on_failure(:raise) }
      def by_repository_id(push_ids:, repository_id:)
        results = ::Push.where(repository_id: repository_id, id: push_ids).to_a
        GH::Domain::Collection.new(results)
      end

      # Fetches an Array of pushes for given repository and refs ordered by pushed_at & id: desc
      # Optionally limit or offset the query
      # Appears to hit `index_pushes_on_repository_id_and_ref_and_pushed_at` index.
      sig do
        params(
          repository_id: Integer,
          refs: T::Array[String],
          pushed_before: T.nilable(T.any(Time, ActiveSupport::TimeWithZone)),
          offset: T.nilable(Integer),
          limit: T.nilable(Integer))
        .returns(GH::Domain::Collection[Repositories::IPush])
        .checked(:always)
        .on_failure(:raise)
      end
      def by_repository_id_and_refs(repository_id:, refs:, pushed_before: nil, offset: nil, limit: nil)
        query = ::Push
          .where(repository_id: repository_id, ref: refs)
          .order(pushed_at: :desc, id: :desc)

        if pushed_before
          query = query.where(pushed_at: ..pushed_before)
        end

        results = query
          .offset(offset)
          .limit(limit)
          .to_a

        GH::Domain::Collection.new(results)
      end

      # Returns the last time a ref was added or deleted to this repo
      sig { params(repository_id: ::Integer, limit_execution_ms: Integer).returns(T.nilable(Time)).checked(:always).on_failure(:raise) }
      def refset_updated_at(repository_id:, limit_execution_ms:)
        ::Push
          .order("id desc") # TODO: Order by pushed_at once we have `index_pushes_on_repository_id_and_push_type_and_pushed_at`
          .where(repository_id: repository_id)
          .branch_creation_or_deletion
          .limit(1)
          .limit_execution_time(limit_ms: limit_execution_ms)
          .pluck(:pushed_at)
          .first
      end

      # Fetches an array of Users who have pushed to the given repository.
      # Optionally filter by ref and after the specified pushed_at date.
      # Users are returned sorted in alphabetical login order
      sig { params(repository: ::Repository, ref: T.nilable(String), pushed_at: T.nilable(Time)).returns(GH::Domain::Collection[::User]).checked(:always).on_failure(:raise) }
      def pushers_for(repository:, ref: nil, pushed_at: nil)
        base_sql = ::Push.where(repository: repository)
        base_sql = base_sql.where(ref: ref) if ref.present?
        base_sql = base_sql.where(pushed_at: pushed_at..) if pushed_at.present?

        pusher_ids = base_sql.distinct.pluck(:pusher_id)
        results = User.where(id: pusher_ids).order(:login).to_a

        GH::Domain::Collection.new(results)
      end

      # Fetches an array of distinct User ids who have pushed to the given repository and ref newer than the specified pushed_at date.
      # Supposed to hit `index_pushes_on_repository_id_and_ref_and_pushed_at` index.
      # "refs/heads/" will be prepended to ref in order to match the expected format of the ref column in the pushes table
      sig { params(repository: ::Repository, ref: ::String, pushed_at: Time).returns(GH::Domain::Collection[Integer]).checked(:always).on_failure(:raise) }
      def pusher_ids_for_ref(repository:, ref:, pushed_at:)
        results = ::Push
          .where(repository: repository, ref: "refs/heads/#{ref}", pushed_at: pushed_at..)
          .distinct
          .pluck(:pusher_id)

        GH::Domain::Collection.new(results)
      end

      # Fetches the push matching the provided repository_id & push_id
      # If no record is found, returns nil
      sig { params(repository_id: Integer, id: Integer).returns(T.nilable(Repositories::IPush)).checked(:always).on_failure(:raise) }
      def by_id_and_repo_id(repository_id:, id:)
        ::Push.find_by(repository_id: repository_id, id: id)
      end

      # Fetches the first push matching the provided repository_id and after SHA
      # Supposed to hit `index_pushes_on_repository_id_and_after` index.
      # Additional optional before and ref params can be used
      # If no record is found, returns nil
      sig { params(repository_id: Integer, after: String, before: T.nilable(String), ref: T.nilable(String)).returns(T.nilable(Repositories::IPush)).checked(:always).on_failure(:raise) }
      def by_repo_id_and_after(repository_id:, after:, before: nil, ref: nil)
        params = {
          repository_id: repository_id,
          after: after,
          before: before,
          ref: ref
        }.compact

        ::Push.find_by(
          params
        )
      end

      # Fetches the first push (ordered by pushed_at desc) matching the provided repository_id,
      # ref/[refs], and optional after SHA
      # Use get_by_repo_id_and_after if an ordering scope is not needed, for better performance
      # Appears to hit `index_pushes_on_repository_id_and_after` index or
      # index_pushes_on_repository_id_and_ref_and_pushed_at if no after is provided.
      # returns nil if no matching record is found
      sig { params(repository_id: Integer, ref: T.any(T::Array[String], String), after: T.nilable(String)).returns(T.nilable(Repositories::IPush)).checked(:always).on_failure(:raise) }
      def latest_by_after_and_ref(repository_id:, ref:, after: nil)
        params = {
          repository_id: repository_id,
          after: after,
          ref: ref
        }.compact

        ::Push
          .where(params)
          .order(pushed_at: :desc)
          .first
      end

      # Returns a count of all the pushes in the DB
      # NOTE: Only for use in GHES installations or in test code due to potential timeouts
      sig { returns(T.nilable(Integer)).checked(:always).on_failure(:raise) }
      def count
        unless GitHub.enterprise? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
          raise "push.count can only be called in enterprise mode or tests"
        end
        ::Push.annotate("cross-shard-query-exempted").count
      end

      # Returns pushes for a given user, exluding pushes to a specific ref
      sig do
        params(
          repository_id: Integer,
          pusher_id: Integer,
          pagination: GH::Pagination::Cursor,
          exclude_ref: T.nilable(String)
        ).returns(GH::Domain::CursorCollection[Repositories::IPush])
      end
      def by_user(repository_id:, pusher_id:, pagination:, exclude_ref: nil)
        scope = ::Push.from("`#{::Push.table_name}` FORCE INDEX (index_pushes_on_repository_id_and_pusher_id_and_pushed_at)")
          .where(repository_id: repository_id, pusher_id: pusher_id)
          .where(["ref <> ?", exclude_ref])
          .not_branch_deletion_push_type
          .order(pushed_at: :desc)

        T.cast(GH::Pagination::Paginator.paginate(
          scope:,
          pagination:,
          sorts: [GH::Pagination::Sort.new(field: "pushed_at", direction: GH::Pagination::Sort::Direction::DESC)],
        ), GH::Domain::CursorCollection[Repositories::IPush])
      end
    end
  end
end
