# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class MobileCapabilities < Resolvers::Base
      type [String, null: true], null: true

      # Default caps equate to the capabilities that are available on github.com
      DOTCOM_CAPABILITIES = %w[
        analytics
        apple_iap
        commit_emails
        discussions
        explore
        help_hub_support
        image_uploading
        notification_type_settings
        push_notifications
        repository_vulnerability_alerts
        report_content
        sponsors
        upsell_ci
        ghes_mobile_support
        auto_merge
        releases
        deployments
        push_settings
        custom_repository_subscriptions
        push_schedules
        pull_request_workflow_improvements
        scrub_video
        video_upload
        security_alert_subscriptions
        deep_linking_scroll_to
        favorite_repository
        customizable_home_nav
        blocking
        repo_contributors
        organization_blocking
        user_lists
        2fa_auth_requests
        home_shortcuts
        linked_issues
        projects_next
        issue_state_reason
        expand_code_lines
        follow_organizations
        alive
        actions
        repository_filters
        branch_comparisons
        merge_queue
        closable_discussions
        file_level_comments
        repository_actions
        tasklists
        update_branch_method
        starred_repositories_search
        update_pull_request_base_branch
        code_search
        copilot_chat
        pr_commits_since_last_seen
        viewer_feature_flags
        workflow_dispatching
        sunset_classic_projects
        client_apps_important_inbox
        fork_repository
        compare_branches
        sub_issues
        close_issue_as_duplicate
        merge_requirements
      ].freeze

      # Proxima should support all dotcom (default) capabilities but there are some edge cases
      # we are working through. In the meantime we can create an exclusionary list here for proxima
      PROXIMA_CAPABILITIES = (DOTCOM_CAPABILITIES - %w[
        explore
        sponsors
        2fa_auth_requests
        merge_requirements
      ]).freeze

      # We need to roll out capabilities to GHES in a more controlled manner.
      ENTERPRISE_CAPABILITIES = {
        "3.0" => %w[ghes_mobile_support],
        "3.1" => %w[
          image_uploading
          auto_merge
          custom_repository_subscriptions
          scrub_video
        ],
        "3.2" => %w[
          deployments
          push_schedules
          video_upload
          pull_request_workflow_improvements
          security_alert_subscriptions
          deep_linking_scroll_to
          favorite_repository
          customizable_home_nav
        ],
        "3.3" => %w[],
        "3.4" => %w[
          releases
          repo_contributors
          home_shortcuts
        ],
        "3.5" => %w[],
        "3.6" => %w[
          discussions
          user_lists
          linked_issues
          issue_state_reason
          expand_code_lines
          follow_organizations
        ],
        "3.8" => %w[
          branch_comparisons
          alive
          actions
        ],
        "3.9" => %w[repository_filters],
        "3.10" => %w[
          closable_discussions
          file_level_comments
        ],
        "3.12" => %w[
          merge_queue
          repository_actions
          update_branch_method
          starred_repositories_search
          update_pull_request_base_branch
        ],
        "3.16" => %w[
          client_apps_important_inbox
        ],
        "3.17" => %w[
          sunset_classic_projects
          compare_branches
          fork_repository
          projects_next
        ]
      }

      def resolve
        if GitHub.enterprise?
          # NOTE: using major and minor version number because we do not release updates to patch versions.
          find_enterprise_capabilities(GitHub.major_minor_version_number)
        elsif GitHub.multi_tenant_enterprise?
          PROXIMA_CAPABILITIES
        else
          DOTCOM_CAPABILITIES
        end
      end

      def find_enterprise_capabilities(version)
        # Collects supported GHES capabilities up to the provided version.
        # Uses Gem::Version to avoid collisions when using floats to represent versions
        # e.g. 3.1 is equal to 3.10 but they do not represent the same version
        max_ver = Gem::Version.create(version)
        ENTERPRISE_CAPABILITIES.select { |ver| T.must(Gem::Version.create(ver)) <= max_ver }.values.flatten
      end
    end
  end
end
