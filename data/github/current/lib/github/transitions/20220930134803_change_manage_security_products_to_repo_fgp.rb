# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"

# To run this transition directly (using gh-screen):
#
#   $ cd /data/github/current
#   # First, run the transition in dry-run mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220930134803_change_manage_security_products_to_repo_fgp.rb --verbose | tee -a /tmp/change_manage_security_products_to_repo_fgp.log
#   # Then, run the transition in regular mode
#   $ gudo bin/safe-ruby lib/github/transitions/20220930134803_change_manage_security_products_to_repo_fgp.rb --verbose -w | tee -a /tmp/change_manage_security_products_to_repo_fgp.log
#

module GitHub
  module Transitions
    class ChangeManageSecurityProductsToRepoFgp < Transition
      # Copied from https://github.com/github/github/blob/e7c3b60e58c75cb9b8c7e6f40fbe59f925f03e05/config/system_roles.yml
      SYSTEM_ROLES_CONFIG = <<-YAML
        # Base Roles
        system_roles:
          read:
            base:
            target_type: Repository
            permissions: []
          write:
            base:
            target_type: Repository
            permissions:
              - add_label
              - remove_label
              - close_issue
              - reopen_issue
              - close_pull_request
              - reopen_pull_request
              - add_assignee
              - remove_assignee
              - request_pr_review
              - mark_as_duplicate
              - set_milestone
              - read_code_scanning
              - write_code_scanning
              - create_discussion
              - delete_discussion
              - toggle_discussion_answer
              - toggle_discussion_comment_minimize
              - manage_discussion_spotlights
              - create_discussion_category
              - edit_discussion_category
              - convert_issues_to_discussions
          admin:
            base:
            target_type: Repository
            permissions:
              - add_label
              - remove_label
              - close_issue
              - reopen_issue
              - close_pull_request
              - reopen_pull_request
              - add_assignee
              - delete_issue
              - remove_assignee
              - request_pr_review
              - mark_as_duplicate
              - set_milestone
              - manage_topics
              - manage_settings_discussions
              - manage_settings_wiki
              - manage_settings_projects
              - manage_settings_merge_types
              - manage_settings_pages
              - manage_webhooks
              - manage_deploy_keys
              - edit_repo_metadata
              - set_interaction_limits
              - set_social_preview
              - push_protected_branch
              - read_code_scanning
              - write_code_scanning
              - delete_alerts_code_scanning
              - view_secret_scanning_alerts
              - resolve_secret_scanning_alerts
              - run_org_migration
              - create_discussion
              - create_discussion_announcement
              - create_discussion_category
              - edit_discussion_category
              - delete_discussion_category
              - delete_discussion
              - manage_discussion_spotlights
              - toggle_discussion_answer
              - toggle_discussion_comment_minimize
              - convert_issues_to_discussions
              - create_tag
              - delete_tag
              - view_dependabot_alerts
              - resolve_dependabot_alerts
              - bypass_branch_protection
              - manage_security_products

          # Fine-grained Permissions Roles
          triage:
            base: read
            target_type: Repository
            permissions:
              - add_label
              - remove_label
              - close_issue
              - reopen_issue
              - close_pull_request
              - reopen_pull_request
              - add_assignee
              - remove_assignee
              - request_pr_review
              - mark_as_duplicate
              - set_milestone
              - create_discussion
              - delete_discussion
              - toggle_discussion_answer
              - toggle_discussion_comment_minimize
              - edit_discussion_category
              - create_discussion_category
              - convert_issues_to_discussions
          maintain:
            base: write
            target_type: Repository
            permissions:
              - add_label
              - remove_label
              - close_issue
              - reopen_issue
              - close_pull_request
              - reopen_pull_request
              - add_assignee
              - remove_assignee
              - request_pr_review
              - mark_as_duplicate
              - set_milestone
              - manage_topics
              - manage_settings_wiki
              - manage_settings_projects
              - manage_settings_merge_types
              - manage_settings_pages
              - edit_repo_metadata
              - set_interaction_limits
              - set_social_preview
              - push_protected_branch
              - read_code_scanning
              - write_code_scanning
              - create_discussion
              - delete_discussion
              - create_discussion_announcement
              - create_discussion_category
              - edit_discussion_category
              - delete_discussion_category
              - manage_discussion_spotlights
              - manage_settings_discussions
              - toggle_discussion_answer
              - toggle_discussion_comment_minimize
              - convert_issues_to_discussions
              - create_tag
          security_manager:
            base:
            # target type deferred until org roles are stable
            target_type: # Organization
            permissions:
              - manage_security_products
              - manage_dependabot_alerts_enablement
              - manage_advanced_security_enablement
              - manage_secret_scanning_settings
              - view_security_managers
              - read_code_scanning
              - write_code_scanning
              - delete_alerts_code_scanning
              - view_secret_scanning_alerts
              - resolve_secret_scanning_alerts
              - view_dependabot_alerts
              - resolve_dependabot_alerts
          codespace_org_creator:
            base:
            # target type deferred until org roles are stable
            target_type: # Organization
            permissions:
              - write_org_codespace # create, read, delete org codespaces
          octoshift_migrator:
            base:
            # target type deferred until org roles are stable
            target_type: # Organization
            permissions:
              - run_org_migration
          package_reader:
            base:
            target_type: Package
            permissions:
              - read_package
          package_writer:
            base:
            target_type: Package
            permissions:
              - read_package
              - write_package
          package_admin:
            base:
            target_type: Package
            permissions:
              - read_package
              - write_package
              - admin_package
          team_writer:
            base:
            target_type: Team
            permissions:
              - write_team_post
          project_reader:
            base:
            target_type: MemexProject
            permissions:
              - read_project
          project_writer:
            base:
            target_type: MemexProject
            permissions:
              - read_project
              - write_project
          project_admin:
            base:
            target_type: MemexProject
            permissions:
              - read_project
              - write_project
              - admin_project

        fine_grained_permissions:
          # Memex FGPs
          read_project:
            custom_role_enabled: false
            target_type: MemexProject
          write_project:
            custom_role_enabled: false
            target_type: MemexProject
          admin_project:
            custom_role_enabled: false
            target_type: MemexProject

          # Team FGPs
          write_team_post:
            custom_role_enabled: false
            target_type: Team

          # Package FGPs
          read_package:
            custom_role_enabled: false
            target_type: Package
          write_package:
            custom_role_enabled: false
            target_type: Package
          admin_package:
            custom_role_enabled: false
            target_type: Package

          # octoshift_migrator FGPs
          # note: octoshift_migrator is assigned to Orgs. `admin` also has this FGP but is a repo role
          run_org_migration:
            custom_role_enabled: false
            target_type: Repository

          # Codespace FGPs
          write_org_codespace:
            custom_role_enabled: false
            target_type: Organization

          # Security Manager FGPs
          manage_security_products:
            custom_role_enabled: false
            target_type: Repository
          manage_dependabot_alerts_enablement:
            custom_role_enabled: false
            target_type: Organization
          manage_advanced_security_enablement:
            custom_role_enabled: false
            target_type: Organization
          manage_secret_scanning_settings:
            custom_role_enabled: false
            target_type: Organization
          view_security_managers:
            custom_role_enabled: false
            target_type: Organization

          # Repository FGPs not available to custom roles.
          # todo - why aren't these available to custom roles?
          create_discussion_announcement:
            custom_role_enabled: false
            target_type: Repository
          delete_discussion_category:
            custom_role_enabled: false
            target_type: Repository
          manage_discussion_spotlights:
            custom_role_enabled: false
            target_type: Repository
          manage_settings_discussions:
            custom_role_enabled: false
            target_type: Repository
          create_discussion:
            custom_role_enabled: false
            target_type: Repository

          # Custom role enabled FGPs
          add_label:
            custom_role_enabled: true
            target_type: Repository
          remove_label:
            custom_role_enabled: true
            target_type: Repository
          close_issue:
            custom_role_enabled: true
            target_type: Repository
          reopen_issue:
            custom_role_enabled: true
            target_type: Repository
          close_pull_request:
            custom_role_enabled: true
            target_type: Repository
          reopen_pull_request:
            custom_role_enabled: true
            target_type: Repository
          add_assignee:
            custom_role_enabled: true
            target_type: Repository
          delete_issue:
            custom_role_enabled: true
            target_type: Repository
          remove_assignee:
            custom_role_enabled: true
            target_type: Repository
          request_pr_review:
            custom_role_enabled: true
            target_type: Repository
          mark_as_duplicate:
            custom_role_enabled: true
            target_type: Repository
          set_milestone:
            custom_role_enabled: true
            target_type: Repository
          manage_topics:
            custom_role_enabled: true
            target_type: Repository
          manage_settings_wiki:
            custom_role_enabled: true
            target_type: Repository
          manage_settings_projects:
            custom_role_enabled: true
            target_type: Repository
          manage_settings_merge_types:
            custom_role_enabled: true
            target_type: Repository
          manage_settings_pages:
            custom_role_enabled: true
            target_type: Repository
          manage_webhooks:
            custom_role_enabled: true
            target_type: Repository
          manage_deploy_keys:
            custom_role_enabled: true
            target_type: Repository
          edit_repo_metadata:
            custom_role_enabled: true
            target_type: Repository
          set_interaction_limits:
            custom_role_enabled: true
            target_type: Repository
          set_social_preview:
            custom_role_enabled: true
            target_type: Repository
          push_protected_branch:
            custom_role_enabled: true
            target_type: Repository
          read_code_scanning:
            custom_role_enabled: true
            target_type: Repository
          write_code_scanning:
            custom_role_enabled: true
            target_type: Repository
          delete_alerts_code_scanning:
            custom_role_enabled: true
            target_type: Repository
          view_secret_scanning_alerts:
            custom_role_enabled: true
            target_type: Repository
          resolve_secret_scanning_alerts:
            custom_role_enabled: true
            target_type: Repository
          delete_discussion:
            custom_role_enabled: true
            target_type: Repository
          toggle_discussion_answer:
            custom_role_enabled: true
            target_type: Repository
          toggle_discussion_comment_minimize:
            custom_role_enabled: true
            target_type: Repository
          edit_discussion_category:
            custom_role_enabled: true
            target_type: Repository
          create_discussion_category:
            custom_role_enabled: true
            target_type: Repository
          convert_issues_to_discussions:
            custom_role_enabled: true
            target_type: Repository
          view_dependabot_alerts:
            custom_role_enabled: true
            target_type: Repository
          resolve_dependabot_alerts:
            custom_role_enabled: true
            target_type: Repository
          create_tag:
            custom_role_enabled: true
            target_type: Repository
          delete_tag:
            custom_role_enabled: true
            target_type: Repository
          bypass_branch_protection:
            custom_role_enabled: true
            target_type: Repository
      YAML

      def perform
        config = YAML.load(SYSTEM_ROLES_CONFIG)

        create_roles(config)
        create_fgps(config)
        create_role_permissions(config)
      end

      private

      def create_roles(config)
        return if dry_run?

        affected_rows = 0
        Role.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          config["system_roles"].each do |name, metadata|
            log("creating #{name} role") if verbose?
            if Role.exists?(name: name)
              log("role #{name} already exists, skipping") if verbose?
              next
            end

            base_role_id = Role.find_by(name: metadata["base"])&.id
            base_role_id = "null" if base_role_id.nil?

            target_type = if metadata["target_type"].blank?
              "null"
            else
              "'#{metadata["target_type"]}'"
            end

            # Can't use github_sql builder here because base_role_id and target_type can be null.
            result = ApplicationRecord::Iam.connection.execute(<<-SQL)
              INSERT INTO `roles` (name, base_role_id, target_type, created_at, updated_at)
              VALUES ('#{name}', #{base_role_id}, #{target_type}, now(), now())
            SQL
            affected_rows += result.affected_rows
          end
        end
        log("created #{affected_rows} roles") if verbose?
      end

      def create_fgps(config)
        return if dry_run?

        affected_rows = 0
        FineGrainedPermission.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          config["fine_grained_permissions"].each do |action, metadata|
            log("creating #{action} fgp") if verbose?
            if FineGrainedPermission.exists?(action: action)
              log("action #{action} already exists, skipping") if verbose?
              next
            end

            custom_roles_enabled = metadata["custom_role_enabled"]

            target_type = if metadata["target_type"].blank?
              "null"
            else
              "'#{metadata["target_type"]}'"
            end

            # Can't use github_sql builder here because taret_type can be null.
            result = ApplicationRecord::Iam.connection.execute(<<-SQL)
              INSERT INTO `fine_grained_permissions` (action, target_type, custom_roles_enabled, created_at, updated_at)
              VALUES ('#{action}', #{target_type}, #{custom_roles_enabled}, now(), now())
            SQL
            affected_rows += result.affected_rows
          end
        end
        log("created #{affected_rows} fgps") if verbose?
      end

      def create_role_permissions(config)
        return if dry_run?

        affected_rows = 0
        RolePermission.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          config["system_roles"].each do |name, metadata|
            role = Role.find_by(name: name)
            raise "could not find role #{name}" if role.nil?

            metadata["permissions"].each do |action|
              fgp = FineGrainedPermission.find_by(action: action)
              raise "could not find fgp #{action}" if fgp.nil?

              log("creating role permission for role #{role.name} and fgp #{fgp.action}") if verbose?
              if RolePermission.exists?(role_id: role.id, fine_grained_permission_id: fgp.id)
                log("role permission for role #{role.name} and fgp #{fgp.action} already exists, skipping") if verbose?
                next
              end

              params = {
                role_id: role.id,
                fine_grained_permission_id: fgp.id,
                action: fgp.action
              }

              result = RolePermission.github_sql.run(<<-SQL, params)
                INSERT INTO `role_permissions` (role_id, fine_grained_permission_id, action, created_at, updated_at)
                VALUES (:role_id, :fine_grained_permission_id, :action, now(), now())
              SQL
              affected_rows += result.affected_rows
            end
          end
        end
        log("created #{affected_rows} role_permissions") if verbose?
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby #{__FILE__} [options]"

    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]


  transition = GitHub::Transitions::ChangeManageSecurityProductsToRepoFgp.new(**options)
  transition.run
end
