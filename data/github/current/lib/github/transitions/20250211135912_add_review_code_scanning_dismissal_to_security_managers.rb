# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout this documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/

# To learn about system role transitions, specifically, checkout this documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/authorization/roles-and-fgps/creating-roles-and-fgps/#2-adding-your-roles-and-permissions-to-the-db
module GitHub
  module Transitions
    class AddReviewCodeScanningDismissalToSecurityManagers < Base
      SYSTEM_ROLES_CONFIG = <<-YAML
        # Base Roles
  system_roles:
    read:
      base:
      target_type: Repository
      permissions:
        - read_repo_metadata
        - read_repo
        - read_repo_contents
        - read_repo_pull_requests
        - star_repo
    write:
      base:
      target_type: Repository
      permissions:
        - read_repo_metadata
        - read_repo_contents
        - write_repo_contents
        - add_label
        - remove_label
        - close_issue
        - reopen_issue
        - read_repo_pull_requests
        - write_repo_pull_requests
        - close_pull_request
        - reopen_pull_request
        - add_assignee
        - set_issue_type
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
        - close_discussion
        - reopen_discussion
        - edit_category_on_discussion
        - edit_discussion_comment
        - delete_discussion_comment
        - view_dependabot_alerts
        - resolve_dependabot_alerts
        - manage_discussion_badges
        - read_repo
        - write_repo
        - star_repo
    admin:
      base:
      target_type: Repository
      permissions:
        - read_repo_metadata
        - read_repo_contents
        - write_repo_contents
        - add_label
        - remove_label
        - close_issue
        - reopen_issue
        - read_repo_pull_requests
        - write_repo_pull_requests
        - close_pull_request
        - reopen_pull_request
        - add_assignee
        - delete_issue
        - remove_assignee
        - request_pr_review
        - mark_as_duplicate
        - set_milestone
        - set_issue_type
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
        - manage_repo_security_products
        - edit_repo_protections
        - edit_repo_announcement_banners
        - close_discussion
        - reopen_discussion
        - edit_category_on_discussion
        - manage_discussion_badges
        - edit_discussion_comment
        - delete_discussion_comment
        - read_repo
        - write_repo
        - admin_repo
        - jump_merge_queue
        - create_solo_merge_queue_entry
        - edit_repo_custom_properties_values
        - star_repo
    # Fine-grained Permissions Roles
    triage:
      base: read
      target_type: Repository
      permissions:
        - read_repo_metadata
        - read_repo_contents
        - add_label
        - remove_label
        - close_issue
        - reopen_issue
        - read_repo_pull_requests
        - close_pull_request
        - reopen_pull_request
        - add_assignee
        - remove_assignee
        - request_pr_review
        - mark_as_duplicate
        - set_milestone
        - set_issue_type
        - create_discussion
        - delete_discussion
        - toggle_discussion_answer
        - toggle_discussion_comment_minimize
        - edit_discussion_category
        - create_discussion_category
        - convert_issues_to_discussions
        - close_discussion
        - reopen_discussion
        - edit_category_on_discussion
        - edit_discussion_comment
        - delete_discussion_comment
        - read_repo
        - star_repo
    maintain:
      base: write
      target_type: Repository
      permissions:
        - read_repo_metadata
        - read_repo_contents
        - write_repo_contents
        - add_label
        - remove_label
        - close_issue
        - reopen_issue
        - read_repo_pull_requests
        - write_repo_pull_requests
        - close_pull_request
        - reopen_pull_request
        - add_assignee
        - remove_assignee
        - request_pr_review
        - mark_as_duplicate
        - set_milestone
        - set_issue_type
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
        - edit_repo_announcement_banners
        - close_discussion
        - reopen_discussion
        - edit_category_on_discussion
        - edit_discussion_comment
        - delete_discussion_comment
        - view_dependabot_alerts
        - resolve_dependabot_alerts
        - manage_discussion_badges
        - read_repo
        - write_repo
        - star_repo
    all_repo_read:
      base: read
      target_type: Organization
      permissions: []
    all_repo_triage:
      base: triage
      target_type: Organization
      permissions: []
    all_repo_write:
      base: write
      target_type: Organization
      permissions: []
    all_repo_maintain:
      base: maintain
      target_type: Organization
      permissions: []
    all_repo_admin:
      base: admin
      target_type: Organization
      permissions: []
    ci_cd_admin:
      base:
      target_type: Organization
      permissions:
        - write_organization_actions_settings
        - write_organization_actions_secrets
        - write_organization_actions_variables
        - write_organization_runners_and_runner_groups
        - write_organization_runner_custom_images
        - write_organization_network_configurations
        - read_organization_actions_usage_metrics
    enterprise_security_manager:
      base:
      target_type: Business
      permissions:
        - manage_enterprise_security_products
    security_manager:
      base: read
      target_type: Organization
      permissions:
        - manage_security_products
        - manage_repo_security_products
        - manage_org_security_products
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
        - repo_review_and_manage_secret_scanning_bypass_requests
        - org_review_and_manage_secret_scanning_bypass_requests
        - org_review_and_manage_secret_scanning_closure_requests
        - org_review_and_manage_code_scanning_dismissal_requests
        - org_bypass_secret_scanning_closure_requests
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
    vulnerability_reporter:
      base:
      target_type: Repository
      permissions:
        - read_repo_metadata
        - read_repo_contents
        - write_repo_contents
        - read_repo_pull_requests
        - write_repo_pull_requests
    ref_rules_manager:
      base:
      # target type deferred until org roles are stable
      target_type: # Organization
      permissions:
        - manage_organization_ref_rules
    custom_properties_org_definitions_manager:
      base:
      target_type: # Organization
      permissions:
        - manage_org_custom_properties_definitions
    custom_properties_org_values_editor:
      base:
      target_type: # Organization
      permissions:
        - edit_org_custom_properties_values
      YAML

      sig do
        override.void
      end
      def perform
        config = YAML.load(SYSTEM_ROLES_CONFIG)

        create_roles(config)
        create_role_permissions(config)
      end

      private

      sig do
        params(
          config: T.untyped
        ).void
      end
      def create_roles(config)
        affected_rows = 0

        config["system_roles"].each do |name, metadata|
          log("creating #{name} role") if verbose?
          if Role.exists?(name: name)
            log("role #{name} already exists, skipping") if verbose?
            next
          end

          base_role_id = Role.find_by(name: metadata["base"])&.id

          target_type = if metadata["target_type"].blank?
            nil
          else
            "#{metadata["target_type"]}"
          end

          params = {
            name: name,
            base_role_id: base_role_id,
            target_type: target_type
          }

          if dry_run?
            log("[dry_run] would create role #{name} with base_role_id #{base_role_id} and target_type #{target_type}")
          else
            write_to(model_class: Role) do
              result_affected_rows = Role.connection.update(Arel.sql(<<-SQL, **params))
                  INSERT INTO `roles` (name, base_role_id, target_type, created_at, updated_at)
                  VALUES (:name, :base_role_id, :target_type, now(), now())
              SQL
              affected_rows += result_affected_rows
            end
          end
        end

        log("created #{affected_rows} roles") if verbose?
      end

      sig do
        params(
          config: T.untyped
        ).void
      end
      def create_role_permissions(config)
        affected_rows = 0
        config["system_roles"].each do |name, metadata|
          role = Role.find_by(name: name)
          raise "could not find role #{name}" if role.nil? && !dry_run?

          metadata["permissions"].each do |action|
            log("creating role permission for role #{name} and fgp #{action}") if verbose?
            if role && RolePermission.exists?(role_id: role.id, action: action)
              log("role permission for role #{role.name} and fgp #{action} already exists, skipping") if verbose?
              next
            end

            params = {
              role_id: role&.id,
              action: action
            }

            if dry_run?
              log("[dry_run] would create role_permission with params #{params.inspect}")
            else
              write_to(model_class: RolePermission) do
                result_affected_rows = RolePermission.connection.update(Arel.sql(<<-SQL, **params))
                  INSERT INTO `role_permissions` (role_id, action, created_at, updated_at)
                  VALUES (:role_id, :action, now(), now())
                SQL
                affected_rows += result_affected_rows
              end
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
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::AddReviewCodeScanningDismissalToSecurityManagers.new(args).run
end
