# typed: true
# frozen_string_literal: true

require "set"

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class CandidateCrossReference < Platform::Loader
          include GitHub::ResilienceMixin

          FETCH_LIMIT = 10_000

          # Row indices for cross-reference results returned by fetch_cross_references_skip_source_repos
          # The order matches: [target_id, id, created_at, actor_id, source_id, pull_request_id, source_repository_id, target_repository_id]
          ROW_INDEX_TARGET_ID = 0
          ROW_INDEX_ID = 1
          ROW_INDEX_CREATED_AT = 2
          ROW_INDEX_ACTOR_ID = 3
          ROW_INDEX_SOURCE_ID = 4
          ROW_INDEX_PULL_REQUEST_ID = 5
          ROW_INDEX_SOURCE_REPOSITORY_ID = 6
          ROW_INDEX_TARGET_REPOSITORY_ID = 7

          def self.load(issue_id, viewer, cap_filter: nil)
            self.for(viewer, cap_filter).load(issue_id)
          end

          def initialize(viewer, cap_filter)
            @viewer = viewer
            @cap_filter = cap_filter
          end

          def fetch(issue_ids)
            fetch_placeholders(issue_ids)
          end

          private

          attr_reader :viewer

          PREFILTER_THRESHOLD = 1_000

          def fetch_placeholders(issue_ids)
            results = fetch_cross_references_skip_source_repos(issue_ids)

            prefilter = results.size >= PREFILTER_THRESHOLD &&
              FeatureFlag.vexi.enabled?(:cross_reference_prefilter_permission_check, viewer, default: false)

            if prefilter
              prefiltered_filter_and_build_placeholders(results)
            else
              filter_and_build_placeholders(results)
            end
          end

          def filter_and_build_placeholders(results)
            results_by_issue_id = Hash.new { |hash, key| hash[key] = [] }

            filter_results(results, results_by_issue_id)

            apply_access_filters(results_by_issue_id)

            results_by_issue_id.transform_values! do |results|
              results.map do |result|
                ::Timeline::Placeholder::CrossReference.new(id: result[:id], sort_datetimes: [result[:created_at]])
              end
            end
          end

          def prefiltered_filter_and_build_placeholders(results)
            return filter_and_build_placeholders(results) unless viewer

            source_repo_ids = results.each_with_object(Set.new) { |row, set| set << row[ROW_INDEX_SOURCE_REPOSITORY_ID] }

            # accessible_repository_ids runs ~6 scoped queries against the candidate
            # repo IDs. For large sets this produces large IN clauses, but is still cheaper
            # than running per-repo async_guard permission chains on thousands of
            # inaccessible private repos.
            accessible_ids = Platform::Security::RepositoryAccess.new(viewer)
              .accessible_repository_ids(repository_ids: source_repo_ids.to_a).to_set

            public_repo_ids = Repository.where(id: source_repo_ids.to_a, public: true).pluck(:id).to_set

            internal_repo_ids = internal_repo_ids_for_viewer(source_repo_ids.to_a)

            allowed_repo_ids = accessible_ids | public_repo_ids | internal_repo_ids

            filtered_results = results.select do |row|
              allowed_repo_ids.include?(row[ROW_INDEX_SOURCE_REPOSITORY_ID])
            end

            filter_and_build_placeholders(filtered_results)
          end

          def filter_results(results, results_by_issue_id)
            ids_to_filter = []

            viewer_block_promises = results.map do |(_target_id, id, _created_at, actor_id, _source_id, _pull_request_id, _source_repository_id, _target_repository_id)|
              block_promise = viewer ? Platform::Loaders::UserBlockedCheck.load(viewer.id, actor_id) : Promise.resolve(false)
              block_promise.then do |blocked|
                next unless blocked
                ids_to_filter << id
              end
            end

            # if it's running the experiment, it replaces with_oauth_app_policy_violating_repos_hidden_for
            if viewer&.using_oauth_application?
              source_repository_ids = results.map { |row| row[ROW_INDEX_SOURCE_REPOSITORY_ID] }.uniq
              violated_repo_ids = Repository.oauth_app_policy_violated_repository_ids(
                repository_ids: source_repository_ids,
                repository_scope: Repository.private_scope,
                app: viewer.oauth_application,
              )

              # filter out the violated repositories
              results = results.reject { |row| violated_repo_ids.include?(row[ROW_INDEX_SOURCE_REPOSITORY_ID]) }
            end

            owner_block_promise_cache = {}

            all_repository_ids = results.flat_map { |row| [row[ROW_INDEX_SOURCE_REPOSITORY_ID], row[ROW_INDEX_TARGET_REPOSITORY_ID]] }.uniq

            repos = {}
            repos_promise = load_repositories_with_individual_permission_check(all_repository_ids, results, repos)

            cross_refs_promises = repos_promise.then do
              Promise.all(results.map do |(target_id, id, created_at, actor_id, _source_id, pull_request_id, source_repository_id, target_repository_id)|
                target_repository = repos[target_repository_id]
                source_repository = repos[source_repository_id]

                next unless source_repository && target_repository
                next if pull_request_id.nil? && !source_repository.has_issues

                owner_blocking_promise = owner_block_promise_cache[[target_repository.owner_id, actor_id]] || Platform::Loaders::UserBlockedCheck.load(target_repository.owner_id, actor_id)
                owner_block_promise_cache[[target_repository.owner_id, actor_id]] = owner_blocking_promise

                owner_blocking_promise.then do |blocked_by_target_repository_owner|
                  next false if blocked_by_target_repository_owner
                  # no access if the repo is private and there is no viewer
                  next false unless source_repository.public? || viewer

                  repo_check_promise = if GitHub.site_admin_can_see_private_repo? && !source_repository.public?
                    # enterprise site admins can see that private repos exists, but they cannot see the content
                    # this check can be skipped when not running on enterprise for performance reason
                    Platform::Loaders::AssociatedRepositoryCheck.load(viewer, source_repository_id)
                  else
                    Promise.resolve(true)
                  end

                  repo_check_promise.then do |accessible|
                    next unless accessible
                    results_by_issue_id[target_id] << { id: id, created_at: created_at, source_repository: source_repository }
                  end
                end
              end)
            end

            Promise.all([cross_refs_promises] + viewer_block_promises).sync

            results_by_issue_id.transform_values! do |results|
              results = results.filter { |result| !ids_to_filter.include?(result[:id]) }
            end
          end

          def load_repositories_with_individual_permission_check(all_repository_ids, results, repos)
            # Batch load all unique repository IDs at once to avoid N+1 permission checks
            Platform::Loaders::ActiveRecord.load_all(
              ::Repository,
              all_repository_ids,
              security_violation_behaviour: :nil,
              security_unavailable_behavior: :filter,
              candidate_user_permission_check: true
            ).then do |loaded_repos|
              # Build a hash of repository_id => repository for quick lookup.
              # Note: load_all returns an array in the same order as input IDs,
              # with nil for inaccessible repositories (security_violation_behaviour: :nil).
              loaded_repos_by_id = all_repository_ids.zip(loaded_repos).to_h

              results.each do |(_target_id, _id, _created_at, _actor_id, _source_id, pull_request_id, source_repository_id, target_repository_id)|
                source_repository = loaded_repos_by_id[source_repository_id]
                target_repository = loaded_repos_by_id[target_repository_id]

                next unless source_repository
                # if it's running the experiment, it replaces with_issues_from_spammy_repositories_hidden_for
                if GitHub.spamminess_check_enabled? && !viewer&.site_admin?
                  next if !source_repository.active?
                  next if source_repository.user_hidden?
                end
                next if source_repository.disabled_at && (viewer.nil? || !viewer.site_admin?)
                next if pull_request_id.nil? && !source_repository.has_issues

                repos[source_repository_id] = source_repository
                repos[target_repository_id] = target_repository
              end
            end
          end

          def fetch_cross_references_skip_source_repos(issue_ids)
            issues = Issue.where(id: issue_ids).pluck(:id, :repository_id, :locked_at)

            # Group issues by whether they have locked_at to minimize different query patterns
            locked_issues = issues.select { |_, _, locked_at| locked_at.present? }
            unlocked_issues = issues.select { |_, _, locked_at| locked_at.nil? }

            results = []
            issues_hash = issues.to_h { |row| [row[0], row[1]] }

            # Handle unlocked issues in batch (more efficient than UNION)
            unless unlocked_issues.empty?
              unlocked_issue_ids = unlocked_issues.map(&:first)
              results += fetch_cross_references_batch(unlocked_issue_ids, nil)
            end

            # Handle locked issues individually (only when necessary)
            locked_issues.each do |issue_id, _repo_id, locked_at|
              results += fetch_cross_references_batch([issue_id], locked_at)
            end

            results.map do |row|
              target_issue_id = row[0]
              target_issue_repository_id = issues_hash[target_issue_id]

              # Append target repository ID to the row (becomes ROW_INDEX_TARGET_REPOSITORY_ID).
              # If you change this, update the ROW_INDEX_* constants at the top of this class.
              row << target_issue_repository_id

              # need to convert to proper type.
              row[2] = row[2]&.in_time_zone

              row
            end
          end

          # Apply repository filtering and CAP filtering, removing entries that the viewer cannot access.
          def apply_access_filters(results_by_issue_id)
            if ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
              all_results = results_by_issue_id.values.flatten
              repository_ids = all_results.filter_map { |result| result[:source_repository]&.id }.uniq

              filtered_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
                actor: @viewer,
                repository_ids: repository_ids,
              )

              results_by_issue_id.transform_values! do |results|
                results.select { |result| filtered_repository_ids.include?(result[:source_repository].id) }
              end
            end

            if @cap_filter
              source_repositories = results_by_issue_id.values.flatten.filter_map { |h| h[:source_repository] if h[:source_repository]&.active? }
              filtered_source_repository_ids = @cap_filter.authorized_resource_ids(source_repositories)
              results_by_issue_id.transform_values! do |results|
                results.select { |result| filtered_source_repository_ids.include?(result[:source_repository].id) }
              end
            end
          end

          def fetch_cross_references_batch(issue_ids, locked_at_filter)
            scope = ::CrossReference.
              joins(<<~SQL)
                INNER JOIN `issues` `source_issues` ON
                  `cross_references`.`source_repository_id` = `source_issues`.`repository_id` AND
                  `cross_references`.`source_id` = `source_issues`.`id` AND
                  `cross_references`.`source_type` = 'Issue'
              SQL
              .where(
                target_type: "Issue",
                target_id: issue_ids # Use IN clause instead of UNION
              ).
              with_spammy_source_issues_hidden_for(viewer).
              filter_spam_for(viewer)

            scope = scope.where("`cross_references`.`created_at` < ?", locked_at_filter) if locked_at_filter

            # IMPORTANT: The order of these columns must match the ROW_INDEX_* constants defined at the top of this class.
            # If you change the column order here, update the constants accordingly.
            # Note: target_repository_id (ROW_INDEX_TARGET_REPOSITORY_ID) is appended in fetch_cross_references_skip_source_repos.
            select_columns = ["cross_references.target_id",
              "cross_references.id",
              "cross_references.created_at",
              "cross_references.actor_id",
              "cross_references.source_id",
              Arel.sql("CAST(source_issues.pull_request_id as unsigned) as pull_request_id"),
              Arel.sql("CAST(source_issues.repository_id as unsigned) as repository_id")]

            # Return results as arrays to match expected format
            results = scope.select(*select_columns).limit(FETCH_LIMIT) # safety limit to avoid fetching too many rows
            ApplicationRecord::IssuesPullRequests.connection.exec_query(results.to_sql).rows
          end

          def internal_repo_ids_for_viewer(source_repo_ids)
            business_ids = viewer.business_ids(valid_license: true)
            return Set.new if business_ids.empty?

            InternalRepository
              .where(repository_id: source_repo_ids, business_id: business_ids)
              .pluck(:repository_id)
              .to_set
          end
        end
      end
    end
  end
end
