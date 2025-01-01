# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Timeline
      module Placeholders
        class CrossReference < Platform::Loader
          include Scientist

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
            results = fetch_cross_references(issue_ids)
            results_by_issue_id = Hash.new { |hash, key| hash[key] = [] }

            filter_results(results, results_by_issue_id)

            # apply granular access filtering
            if ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
              repository_ids = results_by_issue_id.values.map do |v|
                v.map { |result| result[:source_repository].id }
              end.flatten.uniq

              # TODO(jpemberthy): expose this functionality with a more accesible method, e.g:
              # viewer.accessible_repository_ids_with_api_context
              fitered_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
                actor: @viewer,
                repository_ids: repository_ids,
              )

              results_by_issue_id.transform_values! do |results|
                results.select do |result|
                  fitered_repository_ids.include?(result[:source_repository].id)
                end
              end
            end

            if @cap_filter
              source_repositories = results_by_issue_id.values.flatten.map { |h| h[:source_repository] if h[:source_repository].active? }.uniq.compact
              filtered_source_repository_ids = @cap_filter.authorized_resource_ids(source_repositories)
              results_by_issue_id.transform_values! do |results|
                results.select do |result|
                  filtered_source_repository_ids.include?(result[:source_repository].id)
                end.map do |result|
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

            owner_block_promise_cache = {}
            repos = {}
            repos_promise = Promise.all(results.map do |(_target_id, _id, _created_at, _actor_id, _source_id, pull_request_id, source_repository_id, target_repository_id)|
              # Use security_violation_behaviour: :nil to prevent loading any repos
              # the viewer doesn't have access to see
              Platform::Loaders::ActiveRecord.load_all(::Repository, [source_repository_id, target_repository_id], security_violation_behaviour: :nil, security_unavailable_behavior: :filter, candidate_user_permission_check: true).then do |source_repository, target_repository|
                next unless source_repository
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

          def fetch_cross_references(issue_ids)
            issues = Issue.where(id: issue_ids).pluck(:id, :repository_id, :locked_at)

            source_repository_ids = source_repository_ids(issues)

            # if there are no source repository IDs, return an empty result.
            return [] if source_repository_ids&.empty?

            select_columns = ["cross_references.target_id",
              "cross_references.id",
              "cross_references.created_at",
              "cross_references.actor_id",
              "cross_references.source_id",
              "CAST(source_issues.pull_request_id as unsigned) as pull_request_id",
              "CAST(source_issues.repository_id as unsigned) as repository_id"]

            xref_scopes = create_xref_scopes(issues, select_columns)

            # don't filter if source_repository_ids filter is un-applicable.
            unless source_repository_ids.nil?
              xref_scopes = xref_scopes.map do |xref_scope|
                xref_scope.where("source_issues.repository_id" => source_repository_ids)
              end
            end

            issues_hash = issues.to_h { |row| [row[0], row[1]] }
            union_and_execute_scopes(xref_scopes).map do |row|
              target_issue_id = row[0]
              target_issue_repository_id = issues_hash[target_issue_id]

              # need to append the target repository ID to the row.
              row << target_issue_repository_id

              # need to convert to proper type.
              row[2] = row[2]&.in_time_zone

              row
            end
          end

          def with_issues_from_spammy_repositories_hidden_for(viewer)
            return unless GitHub.spamminess_check_enabled? && !viewer&.site_admin?

            Repository.active.where(user_hidden: false)
          end

          def with_oauth_app_policy_violating_repos_hidden_for(viewer, repo_scope)
            violating_ids = ::CrossReference.oauth_app_policy_violating_repo_ids(viewer)
            return repo_scope unless violating_ids.present?
            # This query looks dangerous, but it's safe because we're narrowing
            # things down in the narrow_repos_to_issue_subset method. We tried
            # to find a way to colocate this narrowing, but couldn't figure out
            # a way to do it without making multiple, extraneous database calls.
            # If we ever need to change this query, we'll need to make sure that
            # it's narrowed down at some point, otherwise we'll be fetching a
            # huge amount of records.
            (repo_scope || Repository).active.where.not(id: violating_ids)
          end

          def create_xref_scopes(issues, columns)
            issues.map do |target_issue_id, target_issue_repository_id, target_issue_locked_at|
              scope = ::CrossReference.
                where(
                  target_type: "Issue",
                  target_id: target_issue_id,
                  target_repository_id: target_issue_repository_id,
                  source_type: "Issue").
                with_valid_source_issue.
                with_spammy_source_issues_hidden_for(viewer).
                filter_spam_for(viewer)

              scope = scope.where("`cross_references`.`created_at` < ?", target_issue_locked_at) if target_issue_locked_at.present?

              scope.select(*columns)
            end
          end

          def union_and_execute_scopes(scopes)
            return [] if scopes.empty?

            # Use "UNION ALL" since each scope is representing a single
            # target issue, so there is no risk for duplicates.
            union_query = scopes.map(&:to_sql).join(" UNION ALL ")

            ApplicationRecord::IssuesPullRequests.
              connection.
              exec_query(union_query).
              rows
          end

          # returns either nil or an array. If nil is returned, no filtering should occur.
          def source_repository_ids(issues)
            repo_scope = with_issues_from_spammy_repositories_hidden_for(viewer)
            repo_scope = with_oauth_app_policy_violating_repos_hidden_for(viewer, repo_scope)

            return nil if repo_scope.nil?
            # If you're ever going to remove or modify the following line,
            # please ensure that you take the
            # with_oauth_app_policy_violating_repos_hidden_for method into
            # account. This method contains a query that will return a ton of
            # data (think millions of records) if the scope is not properly
            # narrowed down by this method. With the narrowing down by this
            # method, the records returned are a much more manageable number (in
            # the thousands).
            repo_scope = narrow_repos_to_issue_subset(repo_scope, issues)
            repo_scope.distinct.pluck(:id)
          end

          def narrow_repos_to_issue_subset(repo_scope, issues)
            xref_scopes = create_xref_scopes(issues, ["source_issues.repository_id"])

            rows = union_and_execute_scopes(xref_scopes)

            issue_repo_ids = rows.map { |row| row[0] }

            repo_scope.where(id: issue_repo_ids)
          end
        end
      end
    end
  end
end
