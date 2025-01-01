# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handler for the MonolithTwirp::Octoshift::Imports::V1::EditRepositoryAPIService
      class EditRepositoryAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::Attribution
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::LiveMigrations
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Repository

        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]
        handles_service MonolithTwirp::Octoshift::Imports::V1::EditRepositoryAPIService

        # Public: Implementation of the EditRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::EditRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::EditRepositoryResponse, or a Twirp::Error.
        def edit_repository(req, env)
          check_model_replication_delay!(Repository)

          repository = replica(Repository).find_by(id: req.id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found", octoshift_error_code: "REPOSITORY_DELETED")
          end

          err = validate(repository, req.action, req.updated_at, req.visibility, req.repository_topics,
                         req.actions_settings)
          return err if err

          # Only update if the incoming updated_at is newer than the latest timestamp on the repository
          err = check_outdated_updated_at(repository, req.updated_at)
          return err if err

          actor = find_mannequin_or_user_by_login(req.user_login) || repository.owner

          rate_limited_mode(repository) do
            if req.action == :LIVE_MIGRATION_ACTION_EDITED
              return edit(repository, actor, req)
            elsif req.action == :LIVE_MIGRATION_ACTION_DELETED
              return delete(repository, actor)
            end
          end
        rescue Errors::UnableToEditError => error
          error.message
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def validate(repository, action, updated_at, visibility, repository_topics, actions_settings)
          if [:LIVE_MIGRATION_ACTION_EDITED, :LIVE_MIGRATION_ACTION_DELETED].exclude?(action)
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "action")
          end
          if updated_at.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "updated_at")
          end

          return if action == :LIVE_MIGRATION_ACTION_DELETED

          if visibility == :REPOSITORY_VISIBILITY_INVALID
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "visibility")
          end
          if repository_topics.any? { |topic| topic.topic_name.blank? }
            return Twirp::Error.invalid_argument("topic_names must be non-empty", argument: "repository_topics")
          end
          if actions_settings&.actions_permission == :ACTIONS_PERMISSION_TYPE_INVALID
            return Twirp::Error.invalid_argument("must be a valid permission type", argument: "actions_permission") # rubocop:disable Style/RedundantReturn
          end
        end

        def edit(repository, actor, req)
          errors = []

          mapped_visibility = map_visibility(req.visibility)
          if repository.visibility != mapped_visibility || repository.archived? != req.is_archived
            result = update_visibility(repository, actor, req.visibility, req.is_archived)

            errors << result.msg if result.is_a?(Twirp::Error)
            errors << "Repository visibility could not be updated" unless repository.visibility == mapped_visibility
            errors << "Repository archived state could not be updated"  unless repository.archived? == req.is_archived
          end

          if repository.default_branch != req.default_branch
            success = ActiveRecord::Base.connected_to(role: :writing) do
              update_default_branch(repository, req.default_branch)
            end

            errors << "Default branch could not be updated" unless success
          end

          repository.name = req.name
          repository.description = req.description
          repository.has_wiki = req.has_wiki
          repository.has_issues = req.has_issues
          repository.has_downloads = req.has_downloads

          rate_limited_mode(repository) do
            unless repository.save
              errors << "Could not update repository: #{repository.errors.full_messages.join(", ")}"
            end
          end

          errors += edit_page_settings(repository, actor, req.page)
          errors += edit_webhooks(repository, req.webhooks)
          errors += edit_autolinks(repository, req.autolinks)
          errors += edit_repository_topics(repository, req.repository_topics)
          errors += edit_security_settings(repository, req.has_dependency_graph, req.has_vulnerability_alerts,
                                 req.has_vulnerability_updates, req.has_advanced_security, req.has_token_scanning,
                                 req.has_token_scanning_push_protection)
          errors += edit_general_repository_settings(repository, actor, req.general_repository_settings) if req.general_repository_settings
          errors += edit_actions_settings(repository, actor, req.actions_settings) if req.actions_settings

          if errors.any?
            # Delimiter is "\n" not a comma, because the errors themselves may contain commas
            raise Errors::UnableToEditError, Twirp::Error.canceled(errors.join("\n"))
          end

          repository.update(updated_at: req.updated_at&.to_time)
          errors << "Could not update repository updated_at" unless repository.updated_at == req.updated_at&.to_time

          build_repository_hash(repository)
        end

        def edit_page_settings(repository, actor, page)
          errors = []

          if page.present? && page.to_json != "{}"
            error = generate_page_visibility_error(repository, page.is_public)
            if error.present?
              return errors << "Page settings could not be updated: #{error}"
            end

            attributes = {
              public: page.is_public,
              source: page.source.presence,
              build_type: page.build_type.presence,
              source_ref_name: page.source_ref_name.presence,
              source_subdir: page.source_subdir.presence
            }
            repository.page ? repository.page.update(attributes) : repository.build_page(attributes)

            # rebuild_pages will also save the page
            unless repository.rebuild_pages(actor)
              return errors << "Page settings could not be updated: couldn't rebuild the pages site"
            end

            # Sometimes needed after page creation 🤷‍♀️
            repository.page.update(public: page.is_public) unless repository.page.public? == page.is_public

            if repository.page.cname_error.present?
              # This happens when the CNAME is invalid or already taken by another repo
              errors << "Page settings could not be updated: #{repository.page.cname_error}"
            end
          elsif repository.page
            # Delete existing page
            unless repository.page.destroy
              errors << "Page could not be deleted"
            end
            # Soft delete the existing page
            # repository.unpublish_page
          end

          errors
        end

        def edit_webhooks(repository, webhooks)
          # Editing a webhook is tricky because we don't have an ID. Delete any existing webhooks on the target repo
          # and recreate from scratch.

          errors = []

          existing_webhooks = Hook.webhooks_for_target(repository)

          errors += ActiveRecord::Base.connected_to(role: :writing) do
            # Delete existing webhooks
            existing_webhooks.each do |webhook|
              errors << "Webhook could not be deleted" unless webhook.destroy
            end

            create_webhooks(repository, webhooks)
          end

          errors
        end

        def create_webhooks(repository, webhooks)
          errors = []

          webhooks.each do |webhook|
            new_webhook = Hook.create(
              installation_target: repository,
              name: "web",
              active: webhook.active,
              config: {
                "url"          => webhook.payload_url,
                "insecure_ssl" => webhook.enable_ssl_verification ? "0" : "1",
                "content_type" => webhook.content_type,
              },
              events: webhook.event_types & valid_repo_event_types
            )

            unless new_webhook.save
              errors << "Webhook could not be created: #{new_webhook.errors.full_messages.to_sentence}"
            end
          end

          errors
        end

        # An autolink isn't editable. This method supports creation/deletion.
        def edit_autolinks(repository, autolinks)
          errors = []

          existing_autolinks = Repositories.domain.key_links.list_for_repo(repository.id)

          # Build lookup hashes
          existing_by_attrs = existing_autolinks.index_by { |al| [al.key_prefix, al.url_template, al.is_alphanumeric] }
          existing_attrs = existing_by_attrs.keys.to_set
          requested_attrs = autolinks.map { |al| [al.key_prefix, al.url_template, al.is_alphanumeric] }.to_set

          # Delete autolinks not present in the request
          (existing_attrs - requested_attrs).each do |attrs|
            autolink = existing_by_attrs[attrs]
            Repositories.domain.key_links.destroy(autolink.id, repo_id: repository.id)
          end

          # Create new autolinks that don't already exist
          new_autolinks = autolinks.reject do |autolink|
            existing_by_attrs.key?([autolink.key_prefix, autolink.url_template, autolink.is_alphanumeric])
          end
          create_autolinks(repository, new_autolinks) unless new_autolinks.empty?

          unless Repositories.domain.key_links.list_for_repo(repository.id).count == autolinks.count
            errors << "Autolinks could not be updated: count mismatch. Ensure key_prefixes and url_templates are valid."
          end

          errors
        end

        def edit_repository_topics(repository, repository_topics)
          existing_topics = repository.repository_topics.includes(:topic).to_a

          ActiveRecord::Base.connected_to(role: :writing) do
            existing_topics.each do |existing_topic|
              # Delete any existing repository topics that are not in the request
              unless repository_topics.any? { |t| t.topic_name == existing_topic.topic.name }
                unless existing_topic.destroy
                  raise Errors::UnableToEditError, Twirp::Error.canceled("Repository topic '#{existing_topic.topic.name}' could not be deleted")
                end
              end
            end
          end

          create_repository_topics(repository, repository_topics)
        end

        def create_repository_topics(repository, repository_topics)
          errors = []

          repository_topics.each do |topic|
            user = find_mannequin_or_user_by_login(topic.creator_login)
            unless user
              errors << "Repository topic '#{topic.topic_name}' could not be created: topic creator '#{topic.creator_login}' not found"
              next
            end

            parent_topic = get_topic_model(topic.topic_name, topic.topic_url)

            repository_topic = RepositoryTopic.new(
              topic: parent_topic,
              repository: repository,
              user: user,
              state: map_repository_topic_state(topic.state),
              created_at: topic.created_at&.to_time,
              updated_at: topic.updated_at&.to_time
            )

            success = ActiveRecord::Base.connected_to(role: :writing) do
              repository_topic.save
            end

            unless success
              validation_errors = repository_topic.errors.full_messages.to_sentence
              next if validation_errors.include?("has already been taken")

              errors << "Repository topic '#{topic.topic_name}' could not be saved: #{validation_errors}"
            end
          end

          errors
        end

        def edit_security_settings(repository, has_dependency_graph, has_vulnerability_alerts,
                                   has_vulnerability_updates, has_advanced_security, has_token_scanning,
                                   has_token_scanning_push_protection)
          errors = []

          ActiveRecord::Base.connected_to(role: :writing) do
            # The dependency graph is enabled by default for public repos and disabled for private repos, so updating
            # the visibility above may have changed the dependency graph state temporarily.
            if repository.dependency_graph_enabled? != has_dependency_graph
              if has_dependency_graph
                repository.enable_dependency_graph(actor: repository.owner)
              else
                repository.disable_dependency_graph(actor: repository.owner)
              end
              errors << "Dependency graph could not be updated" if repository.dependency_graph_enabled? != has_dependency_graph
            end

            if repository.vulnerability_alerts_enabled? != has_vulnerability_alerts
              if has_vulnerability_alerts
                repository.enable_vulnerability_alerts(actor: repository.owner)
              else
                repository.disable_vulnerability_alerts(actor: repository.owner)
              end
              errors << "Vulnerability alerts could not be updated" if repository.vulnerability_alerts_enabled? != has_vulnerability_alerts
            end

            if repository.vulnerability_updates_enabled? != has_vulnerability_updates
              if has_vulnerability_updates
                repository.enable_vulnerability_updates(actor: repository.owner)
              else
                repository.disable_vulnerability_updates(actor: repository.owner)
              end
              errors << "Vulnerability updates could not be updated" if repository.vulnerability_updates_enabled? != has_vulnerability_updates
            end

            if repository.advanced_security_enabled? != has_advanced_security
              if has_advanced_security
                repository.enable_advanced_security(actor: repository.owner)
              else
                repository.disable_advanced_security(actor: repository.owner)
              end
              errors << "GitHub Advanced Security could not be updated" if repository.advanced_security_enabled? != has_advanced_security
            end

            if token_scanning_enabled?(repository) != has_token_scanning
              if has_token_scanning
                SecurityProduct::ServiceManager.new(repository)
                  .toggle_services(repository.owner, services_to_enable: [:token_scanning])
              else
                SecurityProduct::ServiceManager.new(repository)
                  .toggle_services(repository.owner, services_to_disable: [:token_scanning])
              end
              errors << "Secret scanning could not be updated" if token_scanning_enabled?(repository) != has_token_scanning
            end

            if push_protection_enabled?(repository) != has_token_scanning_push_protection
              if has_token_scanning_push_protection
                SecurityProduct::ServiceManager.new(repository)
                  .toggle_services(repository.owner, services_to_enable: [:token_scanning_push_protection])
              else
                SecurityProduct::ServiceManager.new(repository)
                  .toggle_services(repository.owner, services_to_disable: [:token_scanning_push_protection])
              end
              errors << "Secret scanning push protection could not be updated" if push_protection_enabled?(repository) != has_token_scanning_push_protection
            end
          end

          errors
        end

        def token_scanning_enabled?(repository)
          SecurityProduct::TokenScanning.new(repository).enabled?
        end

        def push_protection_enabled?(repository)
          SecurityProduct::TokenScanningPushProtection.new(repository).enabled?
        end

        def edit_general_repository_settings(repository, actor, general_repository_settings)
          errors = []

          if repository.template? != general_repository_settings.is_template&.value
            unless repository.update(template: general_repository_settings.is_template&.value)
              errors << "Template setting could not be updated"
            end
          end

          current_forking = repository.allow_private_repository_forking?
          req_forking = general_repository_settings.has_allow_forking&.value

          if repository.private_repository_forking_configurable?
            if current_forking != req_forking
              if req_forking
                if repository.owner.allow_private_repository_forking?
                  repository.allow_private_repository_forking(actor: actor)
                  errors << "Forking setting could not be enabled" unless repository.allow_private_repository_forking?
                else
                  errors << "Forking setting could not be enabled for the repository because it is not enabled at the organization level"
                end
              else
                repository.block_private_repository_forking(actor: actor)
                errors << "Forking setting could not be disabled" if repository.allow_private_repository_forking?
              end
            end
          elsif current_forking != req_forking
            errors << "Private repository forking setting could not be updated because it is not configurable for this repository"
          end

          if repository.repository_funding_links_enabled? != general_repository_settings.has_sponsorships&.value
            if general_repository_settings.has_sponsorships&.value
              repository.enable_repository_funding_links(actor: actor)
            else
              repository.disable_repository_funding_links(actor: actor)
            end

            if FeatureFlag.vexi.enabled?(:repos_domain_reload, default: false)
              Repositories.domain.reload(repository)
            else
              repository.reload
            end

            if repository.repository_funding_links_enabled? != general_repository_settings.has_sponsorships&.value
              errors << "Sponsorships could not be updated"
            end
          end

          if repository.discussions_on? != general_repository_settings.has_discussions&.value
            if general_repository_settings.has_discussions&.value
              repository.turn_on_discussions(actor: actor)
            else
              repository.turn_off_discussions(actor: actor)
            end

            if repository.discussions_on? != general_repository_settings.has_discussions&.value
              errors << "Discussions could not be updated"
            end
          end

          errors += edit_merge_settings(repository, actor, general_repository_settings)

          if repository.delete_branch_on_merge? != general_repository_settings.has_delete_branch_heads&.value
            if general_repository_settings.has_delete_branch_heads&.value
              repository.allow_auto_deleting_branches(actor: actor)
            else
              repository.disallow_auto_deleting_branches(actor: actor)
            end

            if repository.delete_branch_on_merge? != general_repository_settings.has_delete_branch_heads&.value
              errors << "Auto deleting branch heads setting could not be updated"
            end
          end

          if repository.enable_update_branch? != general_repository_settings.has_update_branch&.value
            repository.update_merge_settings(actor, update_branch_allowed: general_repository_settings.has_update_branch&.value)

            if repository.enable_update_branch? != general_repository_settings.has_update_branch&.value
              errors << "Update branch setting could not be updated"
            end
          end

          if repository.lfs_in_archives_enabled? != general_repository_settings.has_git_lfs_in_archives&.value
            if general_repository_settings.has_git_lfs_in_archives&.value
              repository.enable_lfs_in_archives(actor)
            else
              repository.disable_lfs_in_archives(actor)
            end

            if repository.lfs_in_archives_enabled? != general_repository_settings.has_git_lfs_in_archives&.value
              errors << "Git LFS in archives setting could not be updated"
            end
          end

          if repository.projects_enabled? != general_repository_settings.has_projects&.value
            begin
              if general_repository_settings.has_projects&.value
                repository.enable_repository_projects(actor: actor)
              else
                repository.disable_repository_projects(actor: actor)
              end

              if repository.projects_enabled? != general_repository_settings.has_projects&.value
                errors << "Projects setting could not be updated"
              end
            rescue Repository::ProjectsDependency::CannotEnableProjectsError
              errors << "Projects cannot be enabled when the owning organization/enterprise has projects disabled"
            end
          end

          errors
        end

        def edit_merge_settings(repository, actor, general_repository_settings)
          errors = []

          begin
            repository.update_merge_settings(actor,
              merge_allowed: general_repository_settings.has_merge_commit&.value,
              squash_allowed: general_repository_settings.has_squash_merge&.value,
              rebase_allowed: general_repository_settings.has_rebase_merge&.value,
              auto_merge_allowed: general_repository_settings.has_auto_merge&.value
            )
          rescue Repository::PullRequestDependency::MergeMethodError
            err = "Repository merge settings could not be updated because at least one merge setting must be selected"
            if repository.merge_commit_allowed?
              repository.update_merge_settings(actor, merge_allowed: true)
              err += ". Commit merges were enabled by default." if repository.merge_commit_allowed?

              return errors << err
            end
          end

          if repository.merge_commit_allowed? != general_repository_settings.has_merge_commit&.value
            errors << "Merge commit setting could not be updated"
          end
          if repository.squash_merge_allowed? != general_repository_settings.has_squash_merge&.value
            errors << "Squash merge setting could not be updated"
          end
          if repository.rebase_merge_allowed? != general_repository_settings.has_rebase_merge&.value
            errors << "Rebase merge setting could not be updated"
          end
          if repository.auto_merge_allowed? != general_repository_settings.has_auto_merge&.value
            errors << "Auto merge setting could not be updated"
          end

          errors
        end

        def edit_actions_settings(repository, actor, actions_settings)
          actions_permission = actions_settings.actions_permission

          case actions_permission
          when :ACTIONS_PERMISSION_TYPE_ALL_ENABLED
            return if repository.allows_all_actions?
          when :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
            return if repository.allows_local_actions_only?
          when :ACTIONS_PERMISSION_TYPE_DISABLED
            return if repository.actions_disabled?
          end

          install_actions_app_feature_enabled = repository.owner.feature_flag_enabled?(:octoshift_install_actions_app, default: false)

          if !install_actions_app_feature_enabled
            # For scheduled workflows to run post-migration, launch must be informed
            repository.workflows.select(&:scheduled?).each do |workflow|
              workflow.synchronize_scheduled_workflow_in_launch(repository, actor)
            end
          end

          allows_github_owned_actions = actions_settings.allows_github_owned_actions
          allows_verified_actions = actions_settings.allows_verified_actions
          patterns = actions_settings.patterns

          if actions_permission == :ACTIONS_PERMISSION_TYPE_INHERITED
            # Inherit actions permission from organization
            org = repository.organization

            if org.allows_all_actions?
              actions_permission = :ACTIONS_PERMISSION_TYPE_ALL_ENABLED
            elsif org.allows_local_actions_only?
              actions_permission = :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
            elsif org.allows_specified_actions?
              actions_permission = :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED

              allows_github_owned_actions = org.allows_github_owned_actions?
              allows_verified_actions = org.allows_verified_actions?
              patterns = if org.allows_specific_actions_patterns?
                repository.organization.highest_level_allowlist&.allowed_action_patterns.order(:id).pluck(:value)
              else
                []
              end
            end
          end

          errors = []

          ActiveRecord::Base.connected_to(role: :writing) do
            case actions_permission
            when :ACTIONS_PERMISSION_TYPE_ALL_ENABLED
              repository.enable_actions(actor: actor) if !install_actions_app_feature_enabled
            when :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
              repository.enable_actions(actor: actor) if !install_actions_app_feature_enabled
              repository.enable_local_actions_only
            when :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
              repository.enable_actions(actor: actor) if !install_actions_app_feature_enabled
              repository.enable_specified_actions_only(actor: actor,
                github_owned: allows_github_owned_actions,
                verified: allows_verified_actions,
                patterns: patterns)
            when :ACTIONS_PERMISSION_TYPE_DISABLED
              repository.disable_actions(actor: actor)
            end

            if install_actions_app_feature_enabled
              case actions_permission
              when :ACTIONS_PERMISSION_TYPE_ALL_ENABLED, :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED, :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
                repository.enable_actions(actor: actor)
                unless repository.actions_app_installed?
                  repository.enable_actions_app(actor: actor, entry_point: :twirp_api_octoshift_edit_repository_api_handler_install_actions_app)
                end
              end

              # For scheduled workflows to run post-migration, launch must be informed
              repository.workflows.select(&:scheduled?).each do |workflow|
                workflow.synchronize_scheduled_workflow_in_launch(repository, actor)
              end
            end

            unless repository.save
              return errors << "Actions settings could not be updated: #{repository.errors.full_messages.join(", ")}"
            end

            if actions_permission == :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
              unless repository.allows_github_owned_actions? == allows_github_owned_actions
                errors << "Actions setting allows_github_owned_actions could not be updated"
              end
              unless repository.allows_verified_actions? == allows_verified_actions
                errors << "Actions setting allows_verified_actions could not be updated"
              end
              unless repository.actions_allowlist&.allowed_action_patterns&.pluck(:value)&.sort == patterns&.sort
                errors << "Actions setting patterns could not be updated"
              end
            end
          end

          errors
        end

        def delete(repository, actor)
          ActiveRecord::Base.connected_to(role: :writing) do
            # Soft deletion
            repository.remove(actor, synchronous: true)
          end

          if repository.deleted?
            return build_repository_hash(repository)
          end

          Twirp::Error.canceled("Repository could not be deleted")
        end

        def build_repository_hash(repository)
          {}
        end
      end
    end
  end
end
