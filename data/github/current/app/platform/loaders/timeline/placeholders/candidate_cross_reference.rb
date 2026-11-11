# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class CandidateCrossReference < Platform::Loader

          FETCH_LIMIT = 10_000

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

          def fetch_placeholders(issue_ids)
            results = fetch_cross_references_skip_source_repos(issue_ids)
            results_by_issue_id = Hash.new { |hash, key| hash[key] = [] }

            filter_results(results, results_by_issue_id)

            # apply granular access filtering
            if ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
              repository_ids = results_by_issue_id.values.flat_map { |results| results.filter_map { |result| result[:source_repository]&.id } }.uniq

              # TODO(jpemberthy): expose this functionality with a more accesible method, e.g:
              # viewer.accessible_repository_ids_with_api_context
              filtered_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
                actor: @viewer,
                repository_ids: repository_ids,
              )

              results_by_issue_id.transform_values! do |results|
                results.select do |result|
                  filtered_repository_ids.include?(result[:source_repository].id)
                end
              end
            end

            if @cap_filter
              source_repositories = results_by_issue_id.values.flatten.filter_map { |h| h[:source_repository] if h[:source_repository]&.active? }
              filtered_source_repository_ids = @cap_filter.authorized_resource_ids(source_repositories)
              results_by_issue_id.transform_values! do |results|
                results.select { |result| filtered_source_repository_ids.include?(result[:source_repository].id) }.map do |result|
                  ::Timeline::Placeholder::CrossReference.new(id: result[:id], sort_datetimes: [result[:created_at]])
                end
              end
            else
              results_by_issue_id.transform_values! do |results|
                results.map do |result|
                  ::Timeline::Placeholder::CrossReference.new(id: result[:id], sort_datetimes: [result[:created_at]])
                end
              end
            end
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
              source_repository_ids = results.map { |row| row[6] }.uniq
              violated_repo_ids = Repository.oauth_app_policy_violated_repository_ids(
                # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
                repository_ids: source_repository_ids,
                # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
                repository_scope: Repository.private_scope,
                app: viewer.oauth_application,
              )

              # filter out the violated repositories
              results = results.reject { |row| violated_repo_ids.include?(row[6]) }
            end

            owner_block_promise_cache = {}
            repos = {}
            repos_promise = Promise.all(results.map do |(_target_id, _id, _created_at, _actor_id, _source_id, pull_request_id, source_repository_id, target_repository_id)|
              # Use security_violation_behaviour: :nil to prevent loading any repos
              # the viewer doesn't have access to see
              Platform::Loaders::ActiveRecord.load_all(::Repository, [source_repository_id, target_repository_id], security_violation_behaviour: :nil, security_unavailable_behavior: :filter, candidate_user_permission_check: true).then do |source_repository, target_repository|
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
            end)

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

              # need to append the target repository ID to the row.
              row << target_issue_repository_id

              # need to convert to proper type.
              row[2] = row[2]&.in_time_zone

              row
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
                target_id: issue_ids  # Use IN clause instead of UNION
              ).
              with_spammy_source_issues_hidden_for(viewer).
              filter_spam_for(viewer)

            scope = scope.where("`cross_references`.`created_at` < ?", locked_at_filter) if locked_at_filter

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
        end
      end
    end
  end
end
