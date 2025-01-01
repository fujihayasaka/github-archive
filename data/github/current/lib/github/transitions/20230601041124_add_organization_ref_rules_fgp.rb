# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "optparse"
# Uncomment if you want to use Divvy
# require "divvy"

# To run this transition, checkout the relevant documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/running/
module GitHub
  module Transitions
    class AddOrganizationRefRulesFgp < Transition
      class FineGrainedPermission < ApplicationRecord::Iam; end

      # Copied from https://github.com/github/github/blob/0fd508e3fca3d1c62ad48629ebb2a75469fe7bdb/config/system_roles.yml
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
              - close_discussion
              - reopen_discussion
              - edit_category_on_discussion
              - edit_discussion_comment
              - delete_discussion_comment
              - view_dependabot_alerts
              - resolve_dependabot_alerts
              - manage_discussion_badges
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
              - edit_repo_protections
              - edit_repo_announcement_banners
              - close_discussion
              - reopen_discussion
              - edit_category_on_discussion
              - manage_discussion_badges
              - edit_discussion_comment
              - delete_discussion_comment

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
              - close_discussion
              - reopen_discussion
              - edit_category_on_discussion
              - edit_discussion_comment
              - delete_discussion_comment
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
              - edit_repo_announcement_banners
              - close_discussion
              - reopen_discussion
              - edit_category_on_discussion
              - edit_discussion_comment
              - delete_discussion_comment
              - view_dependabot_alerts
              - resolve_dependabot_alerts
              - manage_discussion_badges
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
          ref_rules_manager:
            base:
            # target type deferred until org roles are stable
            target_type: # Organization
            permissions:
              - manage_organization_ref_rules

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

          # Organization custom role enabled FGPs
          write_organization_custom_org_role:
            custom_role_enabled: true
            target_type: Organization
          read_organization_custom_org_role:
            custom_role_enabled: true
            target_type: Organization
          write_organization_custom_repo_role:
            custom_role_enabled: true
            target_type: Organization
          read_organization_custom_repo_role:
            custom_role_enabled: true
            target_type: Organization
          read_audit_logs:
            custom_role_enabled: true
            target_type: Organization
          manage_organization_webhooks:
            custom_role_enabled: true
            target_type: Organization
          manage_organization_oauth_application_policy:
            custom_role_enabled: true
            target_type: Organization
          manage_organization_actions_self_hosted_runners:
            custom_role_enabled: true
            target_type: Organization
          manage_organization_ref_rules:
            custom_role_enabled: true
            target_type: Organization

          # Repository custom role enabled FGPs
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
          edit_repo_protections:
            custom_role_enabled: true
            target_type: Repository
          edit_repo_announcement_banners:
            custom_role_enabled: true
            target_type: Repository
          close_discussion:
            custom_role_enabled: true
            target_type: Repository
          reopen_discussion:
            custom_role_enabled: true
            target_type: Repository
          edit_category_on_discussion:
            custom_role_enabled: true
            target_type: Repository
          manage_discussion_badges:
            custom_role_enabled: true
            target_type: Repository
          edit_discussion_comment:
            custom_role_enabled: true
            target_type: Repository
          delete_discussion_comment:
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
        affected_rows = 0
        config["system_roles"].each do |name, metadata|
          Role.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log("creating #{name} role") if verbose?
            if readonly { Role.exists?(name: name) }
              log("role #{name} already exists, skipping") if verbose?
              next
            end

            base_role_id = readonly { Role.find_by(name: metadata["base"])&.id }
            base_role_id = "null" if base_role_id.nil?

            target_type = if metadata["target_type"].blank?
              "null"
            else
              "'#{metadata["target_type"]}'"
            end

            if dry_run?
              log("[dry_run] would create role #{name} with base_role_id #{base_role_id} and target_type #{target_type}")
            # Can't use github_sql builder here because base_role_id and target_type can be null.
            else
              result = ApplicationRecord::Iam.connection.execute(<<-SQL)
                INSERT INTO `roles` (name, base_role_id, target_type, created_at, updated_at)
                VALUES ('#{name}', #{base_role_id}, #{target_type}, now(), now())
              SQL
              affected_rows += result.affected_rows
            end
          end
        end
        log("created #{affected_rows} roles") if verbose?
      end

      def create_fgps(config)
        affected_rows = 0
        config["fine_grained_permissions"].each do |action, metadata|
          FineGrainedPermission.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            log("creating #{action} fgp") if verbose?
            if readonly { FineGrainedPermission.exists?(action: action) }
              log("action #{action} already exists, skipping") if verbose?
              next
            end

            custom_roles_enabled = metadata["custom_role_enabled"]

            target_type = if metadata["target_type"].blank?
              "null"
            else
              "'#{metadata["target_type"]}'"
            end

            if dry_run?
              log("[dry_run] would create fgp #{action} with custom_roles_enabled #{custom_roles_enabled} and target_type #{target_type}")
            else
              # Can't use github_sql builder here because taret_type can be null.
              result = ApplicationRecord::Iam.connection.execute(<<-SQL)
                INSERT INTO `fine_grained_permissions` (action, target_type, custom_roles_enabled, created_at, updated_at)
                VALUES ('#{action}', #{target_type}, #{custom_roles_enabled}, now(), now())
              SQL
              affected_rows += result.affected_rows
            end
          end
        end
        log("created #{affected_rows} fgps") if verbose?
      end

      def create_role_permissions(config)
        return if dry_run? # This method doesn't actually work w/ dry runs in its current form.

        affected_rows = 0
        config["system_roles"].each do |name, metadata|
          RolePermission.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            role = readonly { Role.find_by(name: name) }
            raise "could not find role #{name}" if role.nil?

            metadata["permissions"].each do |action|
              fgp = readonly { FineGrainedPermission.find_by(action: action) }
              raise "could not find fgp #{action}" if fgp.nil?

              log("creating role permission for role #{role.name} and fgp #{fgp.action}") if verbose?
              if readonly { RolePermission.exists?(role_id: role.id, fine_grained_permission_id: fgp.id) }
                log("role permission for role #{role.name} and fgp #{fgp.action} already exists, skipping") if verbose?
                next
              end

              params = {
                role_id: role.id,
                fine_grained_permission_id: fgp.id,
                action: fgp.action
              }

              if dry_run?
                log("[dry_run] would create role_permission with params #{params.inspect}")
              else
                result_affected_rows = RolePermission.connection.update(Arel.sql(<<-SQL, **params))
                  INSERT INTO `role_permissions` (role_id, fine_grained_permission_id, action, created_at, updated_at)
                  VALUES (:role_id, :fine_grained_permission_id, :action, now(), now())
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
  options = {}

  OptionParser.new do |opts|
    opts.on("-w", "--write", "Enable writes for the transition - this defaults to false (i.e. a dry_run mode) for safety.") do
      options[:write] = true
    end

    opts.on("-v", "--verbose", "Log verbose output") do
      options[:verbose] = true
    end
  end.parse!

  options[:dry_run] = !options[:write]

  # If choosing to run this transition as a single process, uncomment the below commands:
  transition = GitHub::Transitions::AddOrganizationRefRulesFgp.new(**options)
  transition.run
end
