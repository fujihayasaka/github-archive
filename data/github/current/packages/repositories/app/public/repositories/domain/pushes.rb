# rubocop:disable Metrics/MethodLength
# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Pushes < GH::Domain::Base
      decorate_with GH::Decorator::TestBedIdCaching, only: [:by_id_and_repo_id]

      # Fetches pushes for given repository and pusher newer than specified pushed_at date.
      # Supposed to hit `index_pushes_on_repository_id_and_pusher_id_and_pushed_at` index.
      #
      # Serves data for `recently_touched_branches_for` method,
      # that gets the repository's three branches whose heads were most recently touched by the specified user.
      # pushed_at param is always set to 1.hour.ago
      sig { params(repository_id: Integer, pusher_id: Integer, pushed_at: Time).returns(GH::Domain::Collection[Repositories::Push]).checked(:always).on_failure(:raise) }
      def latest_for(repository_id:, pusher_id:, pushed_at:)
        results = ::Push
          .where(repository_id: repository_id, pusher_id: pusher_id, pushed_at: pushed_at..)
          .order(pushed_at: :desc)
          .to_a


        GH::Domain::Collection.new(Push.from_records(results))
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
      sig { params(repository_id: ::Integer, ref: ::String, pusher_id: Integer, pushed_at: Time).returns(T::Boolean).checked(:always).on_failure(:raise) }
      def exists_for_ref(repository_id:, ref:, pusher_id:, pushed_at:)
        ::Push
          .where(repository_id: repository_id, ref: "refs/heads/#{ref}", pusher_id: pusher_id, pushed_at: pushed_at..)
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
      sig { params(repository_id: Integer, pushed_at: Time, limit: T.nilable(Integer)).returns(GH::Domain::Collection[Repositories::Push]).checked(:always).on_failure(:raise) }
      def latest(repository_id:, pushed_at:, limit: nil)
        results = ::Push
          .where(repository_id: repository_id, pushed_at: pushed_at..)
          .limit(limit)
          .order(pushed_at: :desc)
          .to_a


        GH::Domain::Collection.new(Push.from_records(results))
      end

      # Fetches the last push for a given repository
      # Returns nil if no matching record is found
      #
      # Serves data for `test_webhook` method from `webhook_dependency`,
      # and at the same time used in many tests as a helper method,
      # to fetch a push for a corresponding pull_request/notification/check_suite/etc.
      sig { params(repository_id: Integer).returns(T.nilable(Repositories::Push)).checked(:always).on_failure(:raise) }
      def latest_for_repo(repository_id:)
        result = ::Push
          .where(repository_id: repository_id)
          .order(pushed_at: :desc).first

        Push.from_record(result)
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
      sig { params(push_ids: T::Array[Integer], repository_id: Integer).returns(GH::Domain::Collection[Repositories::Push]).checked(:always).on_failure(:raise) }
      def load_pushes_for_repository(push_ids:, repository_id:)
        results = ::Push.where(repository_id: repository_id, id: push_ids).order(id: :desc).to_a

        GH::Domain::Collection.new(Push.from_records(results))
      end

      # Public: Fetch pushes for the given repository_id and given ids.
      #
      # Options:
      # - push_ids - The ids of the pushes to fetch.
      # - repository_id - The repository to fetch the pushes for.
      #
      # Returns an array of Pushes
      sig { params(push_ids: T::Array[Integer], repository_id: Integer).returns(GH::Domain::Collection[Repositories::Push]).checked(:always).on_failure(:raise) }
      def by_repository_id(push_ids:, repository_id:)
        results = ::Push.where(repository_id: repository_id, id: push_ids).to_a

        GH::Domain::Collection.new(Push.from_records(results))
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
        .returns(GH::Domain::Collection[Repositories::Push])
        .checked(:always)
        .on_failure(:raise)
      end
      def by_repository_id_and_refs(repository_id:, refs:, pushed_before: nil, offset: nil, limit: nil) # rubocop:todo Metrics/MethodLength
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

        GH::Domain::Collection.new(Push.from_records(results))
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
      sig { params(repository_id: Integer, ref: T.nilable(String), pushed_at: T.nilable(Time)).returns(GH::Domain::Collection[Users::IUser]).checked(:always).on_failure(:raise) }
      def pushers_for(repository_id:, ref: nil, pushed_at: nil)
        base_sql = ::Push.where(repository_id: repository_id)
        base_sql = base_sql.where(ref: ref) if ref.present?
        base_sql = base_sql.where(pushed_at: pushed_at..) if pushed_at.present?

        pusher_ids = base_sql.distinct.pluck(:pusher_id)
        results = Users.domain.by_ids(pusher_ids).sort_by { |u| [u.display_login] }

        GH::Domain::Collection.new(results)
      end

      # Fetches an array of distinct User ids who have pushed to the given repository and ref newer than the specified pushed_at date.
      # Supposed to hit `index_pushes_on_repository_id_and_ref_and_pushed_at` index.
      # "refs/heads/" will be prepended to ref in order to match the expected format of the ref column in the pushes table
      sig { params(repository_id: Integer, ref: ::String, pushed_at: Time).returns(GH::Domain::Collection[Integer]).checked(:always).on_failure(:raise) }
      def pusher_ids_for_ref(repository_id:, ref:, pushed_at:)
        results = ::Push
          .where(repository_id: repository_id, ref: "refs/heads/#{ref}", pushed_at: pushed_at..)
          .distinct
          .pluck(:pusher_id)

        GH::Domain::Collection.new(results)
      end

      # Fetches the push matching the provided repository_id & push_id
      # If no record is found, returns nil
      sig { params(repository_id: Integer, id: Integer).returns(T.nilable(Repositories::Push)).checked(:always).on_failure(:raise) }
      def by_id_and_repo_id(repository_id:, id:)
        result = ::Push.find_by(repository_id: repository_id, id: id)

        result.present? ? Push.from_record(result) : nil
      end

      # Fetches the pushes matching the provided id(s)
      sig { params(ids: T::Array[Integer]).returns(GH::Domain::Collection[Repositories::Push]).checked(:always).on_failure(:raise) }
      def by_ids(ids:)
        pushes = GitHub::SQLCheckers::TableSharding.allowing_cross_shard_queries do
          ::Push.where(id: ids).order(id: :desc).to_a
        end

        GH::Domain::Collection.new(Push.from_records(pushes))
      end

      # Fetches the first push matching the provided repository_id and after SHA
      # Supposed to hit `index_pushes_on_repository_id_and_after` index.
      # Additional optional before and ref params can be used
      # If no record is found, returns nil
      sig { params(repository_id: Integer, after: String, before: T.nilable(String), ref: T.nilable(String)).returns(T.nilable(Repositories::Push)).checked(:always).on_failure(:raise) }
      def by_repo_id_and_after(repository_id:, after:, before: nil, ref: nil)
        params = {
          repository_id: repository_id,
          after: after,
          before: before,
          ref: ref
        }.compact

        result = ::Push.find_by(
          params
        )

        Push.from_record(result)
      end

      # Fetches the first push (ordered by pushed_at desc) matching the provided repository_id,
      # ref/[refs], and optional after SHA
      # Use get_by_repo_id_and_after if an ordering scope is not needed, for better performance
      # Appears to hit `index_pushes_on_repository_id_and_after` index or
      # index_pushes_on_repository_id_and_ref_and_pushed_at if no after is provided.
      # returns nil if no matching record is found
      sig { params(repository_id: Integer, ref: T.any(T::Array[String], String), after: T.nilable(String)).returns(T.nilable(Repositories::Push)).checked(:always).on_failure(:raise) }
      def latest_by_after_and_ref(repository_id:, ref:, after: nil)
        by_after_and_refs(
          repository_id:,
          after:,
          refs: Array(ref),
          pagination: GH::Pagination::Cursor.new(first: 1)
        ).first
      end

      # Retrieves a collection of pushes based on the provided repository ID, after SHA, refs, and pagination options.
      # Pushes are ordered by pushed_at in descending order.
      sig do
        params(
          repository_id: Integer,
          after: T.nilable(String),
          refs: T::Array[String],
          pagination: GH::Pagination::Cursor,
        ).returns(GH::Domain::CursorCollection[Repositories::Push])
      end
      def by_after_and_refs(repository_id:, after:, refs:, pagination:)
        params = {
          repository_id: repository_id,
          after: after,
          ref: refs
        }.compact

        scope = ::Push
          .where(params)
          .order(pushed_at: :desc)

        T.cast(GH::Pagination::Paginator.paginate(
          scope:,
          pagination:,
          sorts: [GH::Pagination::Sort.new(field: "pushed_at", direction: GH::Pagination::Sort::Direction::DESC)],
          member_value_class: Push
        ), GH::Domain::CursorCollection[Repositories::Push])
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
        ).returns(GH::Domain::CursorCollection[Repositories::Push])
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
          member_value_class: Push
        ), GH::Domain::CursorCollection[Repositories::Push])
      end

      # Returns pages of pushes for a given repository, optionally filtered by activity type, actor, and time.
      # This is optimized for use in the activity view and related APIs.
      sig do params(
        repository_id: Integer,
        pagination: GH::Pagination::Cursor,
        sort: GH::Pagination::Sort::Direction,
        ref: T.nilable(String),
        activity_type: T.nilable(String),
        pusher_id: T.nilable(Integer),
        pushed_after: T.nilable(Time),
      ).returns(GH::Domain::CursorCollection[Repositories::Push])
      end
      def by_activity_filters(repository_id:, pagination:, sort: GH::Pagination::Sort::Direction::DESC, ref: nil, activity_type: "all", pusher_id: nil, pushed_after: nil) # rubocop:todo Metrics/MethodLength
        scope = ::Push.where(repository_id: repository_id).order(pushed_at: sort.serialize, id: sort.serialize)
        scope = scope.where(ref: ref) if ref.present?

        case activity_type
        when "push"
          scope = scope.push_push_type
        when "force_push"
          scope = scope.force_push_push_type
        when "branch_creation"
          scope = scope.branch_creation_push_type
        when "branch_deletion"
          scope = scope.branch_deletion_push_type
        when "pr_merge"
          scope = scope.pr_merge_push_type
        when "direct_push"
          scope = scope.direct_push
        when "merge_queue_merge"
          scope = scope.merge_queue_merge_push_type
        end

        scope = scope.where(pusher_id:) if pusher_id.present?
        scope = scope.where(pushed_at: pushed_after..) if pushed_after.present?

        # If our only where clauses are for `repository_id` or `pushed_at`, we should hit `repository_id_and_pushed_at_index` index.
        # However MySQL occasionally chooses a different index and the query becomes slow, so use a hint here.
        if scope.where_values_hash.except("repository_id", "pushed_at").empty?
          scope = scope.from("#{::Push.table_name} USE INDEX(index_pushes_on_repository_id_and_pushed_at)")
        end

        T.cast(GH::Pagination::Paginator.paginate(
          scope:,
          pagination:,
          sorts: [GH::Pagination::Sort.new(field: "pushed_at", direction: sort), GH::Pagination::Sort.new(field: "id", direction: sort)],
          lazy_total_entries: -> { scope.count },
          member_value_class: Push
        ), GH::Domain::CursorCollection[Repositories::Push])
      end
    end
  end
end

# rubocop:enable Metrics/MethodLength
