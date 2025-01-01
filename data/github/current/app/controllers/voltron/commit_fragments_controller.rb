# typed: true
# frozen_string_literal: true

module Voltron
  class CommitFragmentsController < AbstractRepositoryController
    include CommitShowMethods
    include ControllerMethods::Commit
    include ControllerMethods::Diffs
    include FragmentController
    include GitHub::RateLimitedRequest

    rate_limit_requests max: 5000, ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, key: :rate_limit_key_by_ip

    # Don't require header in dev or review lab, to simplify nginx configs
    before_action :require_voltron_header, unless: -> { Rails.env.development? || GitHub.dynamic_lab? }

    before_action :mark_commit_as_read, only: :repo_layout

    before_action :require_commit
    javascript_bundle :diffs
    stylesheet_bundle :code
    layout "repository"

    before_action do
      @selected_link = :repo_commits
      @page_responsive = true
    end

    isolate_before_actions :authorization_required,
      :ensure_advisory_workspace_allowed,
      :network_privilege_check,
      :perform_conditional_access_checks,
      to: :repo_layout

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::NotificationsSummaries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Ballast,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      only: [:repo_layout]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      ApplicationRecord::RepositoriesActionsChecks,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Ballast,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::NotificationsSummaries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      only: [:commit_show_header]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations,
      ApplicationRecord::RepositoriesActionsChecks,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::NotificationsSummaries,
      ApplicationRecord::Ballast,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      only: [:commit_show_contents]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:commit_show_contents, :repo_layout, :commit_show_header],
      optional: true

    def repo_layout # rubocop:todo GitHub/UseRestfulActions
      if react_commit_enabled?
        GitHub.current_span&.set_attribute(GitHub::TaggingHelper::CONTROLLER_TAG, "commit")
        GitHub::TaggingHelper.override_controller_tag(env: env, controller: "commit")

        return CommitController.dispatch(:show, request, response)
      end

      render "voltron/commit/repo_layout", locals: {
        repo: current_repository,
        commit: current_commit
      }
    end

    def commit_show_contents # rubocop:todo GitHub/UseRestfulActions
      if react_commit_enabled?
        # using react - render empty response and return
        head :ok
        return
      end

      # 404 if scoped path isn't in the diff
      return render_404 if path_string.present? && commit_tree_diff_page.nil?

      diff_options = {
        use_summary: true,
        ignore_whitespace: ignore_whitespace?,
        paths: path_string.present? ? [path_string] : [],
      }
      current_commit.set_diff_options(diff_options)

      diff_options[:top_only] = true
      current_commit.set_diff_options(diff_options)

      current_commit.init_diff.apply_auto_load_single_entry_limits!
      current_commit.diff # loads diff
      return render_404 if current_commit.diff.missing_commits?

      view = Commit::ShowView.new(commit: current_commit, repository: current_repository, current_user: current_user)

      preload_commit_comment_data

      begin
        render "commit/_show_contents", locals: {
          commit: current_commit,
          file_list_view: file_list_view,
          show_checks_status: GitHub.actions_enabled?,
          view: view
        }, layout: fragment_layout
      rescue GitRPC::ObjectMissing
        # We shouldn't get here, if we do the repo could be in a bad state
        render_404
      end
    end

    def commit_show_header # rubocop:todo GitHub/UseRestfulActions
      if react_commit_enabled?
        # using react - render empty response and return
        head :ok
        return
      end

      view = Commit::ShowView.new(commit: current_commit, repository: current_repository, current_user: current_user)

      render "commit/_commit_show_header", locals: {
        commit: current_commit,
        show_checks_status: GitHub.actions_enabled?,
        view: view
      }, layout: fragment_layout
    end

    private

    def require_voltron_header
      render_404 if request.headers["HTTP_X_GITHUB_USE_VOLTRON_COMMIT_SHOW"] != "1"
    end

    def require_commit
      render_404 if current_commit.nil?
    end

    # Implemented for use in the view, overriding the default `false` value
    def defer_commit_badges?
      true
    end

    # Implemented for use in the view, overriding the default `false` value
    def defer_status_check_rollups?
      true
    end

    def commit_tree_diff # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @commit_tree_diff ||= current_repository.rpc.read_tree_diff(current_commit.oid)
    end
    helper_method :commit_tree_diff

    # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
    def commit_tree_diff_page # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @commit_tree_diff_page ||= begin
        filenames = commit_tree_diff.map { |c| c["old_file"]["path"] }
        if index = filenames.index(path_string)
          index + 1
        end
      end
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator
    helper_method :commit_tree_diff_page

    def route_supports_advisory_workspaces?
      true
    end

    def mark_commit_as_read
      async_mark_thread_as_read current_commit
    end
  end
end
