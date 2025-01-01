# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      # Handles the creation of import data.
      class ImportRepositoryAPIHandler < Api::Internal::Twirp::Handler
        include Imports::Helpers::ContentCreation
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay
        include Imports::Helpers::Attribution
        include Imports::Helpers::AlreadyExists
        include Imports::Helpers::Repository

        WARNING_MESSAGES = ["Hooks is invalid"].freeze

        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportRepositoryAPIService
        allow_access_for :client, allowed_clients: %w[octoshift git_src_migrator elm migrations_vnext]
        connected_to_writing_for :import_repository

        # Public: Implementation of the ImportRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportRepositoryResponse, or a Twirp::Error.
        def import_repository(req, env)
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "owner_id")
          end
          if req.name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end
          if req.visibility == :REPOSITORY_VISIBILITY_INVALID
            return Twirp::Error.invalid_argument(
              "must be :REPOSITORY_VISIBILITY_PUBLIC, :REPOSITORY_VISIBILITY_PRIVATE or :REPOSITORY_VISIBILITY_INTERNAL", argument: "visibility")
          end

          import = replica(Import).find_by(id: req.import_id) unless req.import_id.zero?

          unless import
            unless req.user_id.positive?
              return Twirp::Error.invalid_argument("must be positive integer", argument: "user_id", value: req.user_id.to_s)
            end
            user = replica(User).find_by(id: req.user_id)
            return Twirp::Error.not_found("User not found.") unless user

            import = Import.new({ creator: user })
            ActiveRecord::Base.connected_to(role: :writing) do
              unless import.save
                Twirp::Error.canceled("Could not create import: #{import.errors.full_messages.join(", ")}")
              end
            end
          end

          owner = replica(User).find_by(id: req.owner_id)
          unless owner
            return Twirp::Error.not_found("Owner not found.", argument: "owner_id", value: req.owner_id.to_s)
          end

          if owner.deleted?
            return Twirp::Error.not_found("Owner is being deleted, so new repository cannot be created.", argument: "owner_id", value: req.owner_id.to_s, octoshift_error_code: "OWNER_DELETED")
          end

          begin
            check_for_existing_record!(
              Repository,
              name: req.name,
              owner: owner,
              active: true
            )
          rescue Api::Internal::Twirp::Octoshift::Errors::AlreadyExists => error
            return error.to_twirp_error
          end

          repo_attributes = {
            import: import,
            visibility: map_visibility(req.visibility),
            name: req.name
          }

          result = rate_limited_mode(Repository, throttle: false) do
            Repository.handle_creation(
              import.creator,
              owner.login,
              repo_attributes,
              role: has_octoshift_migrator_role?(import.creator, owner.login) ? :octoshift_migrator : nil
            )
          end

          if result.success?
            repo = result.repository
            create_wiki = req.create_wiki

            # Disable actions on the repository
            repo.disable_actions(actor: owner)

            # Mark repository as being imported
            if req.name != "gei-migration-results"
              ImportExport.domain.importing_started!(repo)
            end

            # Add the migrator to the Repository
            repo.add_member(import.creator, action: :admin)

            # Set max size for repository from the request if it is present
            if req.respond_to?(:max_object_size) && (req.max_object_size && req.max_object_size > 0)
              repo.set_max_object_size(req.max_object_size, import.creator)
            end

            # Initialize empty wiki for migrating wiki data
            create_empty_wiki(repo, import.creator) if create_wiki

            {
              repository: build_repository_hash(result.repository, create_wiki)
            }
          else
            if !result.allowed
              Twirp::Error.permission_denied("#{import.creator.login} cannot create a repository for #{owner.login}")
            else
              error = result.repository.errors.full_messages.join(", ").presence || result.error_message

              if return_repository_creation_policy_failure_errors?
                twirp_error_args = [error]
                twirp_error_args << { octoshift_error_code: "REPOSITORY_CREATION_POLICY_VIOLATION" } if result.error_message&.include?("Due to policy")

                Twirp::Error.canceled(*twirp_error_args)
              else
                Twirp::Error.canceled(error)
              end
            end
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the UpdateRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::UpdateRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::UpdateRepositoryResponse, or a Twirp::Error.
        def update_repository(req, env)
          unless req.repository_id.positive?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          update_branch_successful = ActiveRecord::Base.connected_to(role: :writing) do
            update_default_branch(repository, req.default_branch)
          end

          unless update_branch_successful
            return Twirp::Error.not_found("Branch not found.", argument: "default_branch", value: req.default_branch, current_default_branch: repository.default_branch)
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            repository.update(
              description: req.description,
              has_wiki: req.has_wiki,
              has_issues: req.has_issues,
              has_downloads: req.has_downloads
            )
          end

          security_setting_errors = []
          owner = repository.owner

          ActiveRecord::Base.connected_to(role: :writing) do
            if req.has_dependency_graph
              repository.enable_dependency_graph(actor: owner)
              security_setting_errors << "Dependency graph could not be enabled." unless repository.dependency_graph_enabled?
            end

            if req.has_vulnerability_alerts
              repository.enable_vulnerability_alerts(actor: owner)
              security_setting_errors << "Dependabot alerts could not be enabled." unless repository.vulnerability_alerts_enabled?
            end

            if req.has_vulnerability_updates
              repository.enable_vulnerability_updates(actor: owner)
              security_setting_errors << "Dependabot security updates could not be enabled." unless repository.vulnerability_updates_enabled?
            end

            if req.has_advanced_security
              repository.enable_advanced_security(actor: owner)
              security_setting_errors << "GitHub Advanced Security could not be enabled." unless repository.advanced_security_enabled?
            end

            if req.has_token_scanning
              SecurityProduct::ServiceManager.new(repository).toggle_services(owner, services_to_enable: [:token_scanning])
              token_scanning = SecretScanning::Features::Repo::TokenScanning.new(repository)
              security_setting_errors << "Secret scanning could not be enabled." unless token_scanning.enabled?
            end

            if req.has_token_scanning_push_protection
              SecurityProduct::ServiceManager.new(repository).toggle_services(owner, services_to_enable: [:token_scanning_push_protection])
              push_protection = SecretScanning::Features::Repo::PushProtection.new(repository)
              security_setting_errors << "Secret scanning push protection could not be enabled." unless push_protection.enabled?(ignore_import: true)
            end
          end

          general_setting_errors = ActiveRecord::Base.connected_to(role: :writing) do
            update_general_settings(repository, owner, req.general_repository_settings) if req.general_repository_settings.present?
          end || []

          page_validation_error = ActiveRecord::Base.connected_to(role: :writing) do
            update_page_settings(repository, req.page) if req.page.present?
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            hooks = create_webhooks(repository, req.webhooks) if req.webhooks.present?
            hooks ||= []
            create_repository_topics(repository, req.repository_topics) if req.repository_topics.present?
            create_autolinks(repository, req.autolinks) if req.autolinks.present?
            hooks_valid = hooks.all?(&:valid?)

            unless repository.save && hooks_valid
              unless hooks_valid
                repository.errors.add(:hooks, "is invalid")
              end

              error_messages = repository.errors.full_messages
              if error_messages.all? { |msg| WARNING_MESSAGES.include?(msg) }
                # remap webhook message
                error_messages = error_messages.map do |msg|
                  msg == "Hooks is invalid" ? "One or more webhooks could not be imported. Some webhooks may have been successfully imported." : msg
                end
                error_details = error_messages.join(", ")

                general_setting_errors << error_details

                error_payload = {
                  "code.function" => "update_repository",
                  "gh.repo.id" => req.repository_id,
                  "exception.message" => error_details,
                  "code.namespace" => "import_repository_api_handler"
                }
                GitHub.logger.warn(error_details, error_payload)
              else
                error_message = "Repository update failed"
                error_details = repository.errors.full_messages.join(", ")
                error_payload = {
                  "code.function" => "update_repository",
                  "gh.repo.id" => req.repository_id,
                  "exception.message" => error_details,
                  "code.namespace" => "import_repository_api_handler"
                }

                GitHub.logger.error(error_message, error_payload)

                return Twirp::Error.canceled(error_message, error_details: error_details)
              end
            end
          end

          { repository: build_repository_hash(repository, req.has_wiki, page_validation_error, security_setting_errors, general_setting_errors) }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the UpdateRepositoryVisibility Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::UpdateRepositoryVisibilityRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::UpdateRepositoryVisibilityResponse, or a Twirp::Error.
        def update_repository_visibility(req, env)
          unless req.repository_id.positive?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.visibility == :REPOSITORY_VISIBILITY_INVALID
            return Twirp::Error.invalid_argument(
              "must be :REPOSITORY_VISIBILITY_PUBLIC, :REPOSITORY_VISIBILITY_PRIVATE or :REPOSITORY_VISIBILITY_INTERNAL", argument: "visibility")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          result = update_visibility(repository, repository.owner, req.visibility, req.is_archived)
          return result if result.is_a?(Twirp::Error)

          { repository: build_repository_hash(repository) }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the SetRepositorySequence Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::SetRepositorySequenceRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::SetRepositorySequenceResponse, or a Twirp::Error.
        def set_repository_sequence(req, env)
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          if req.sequence_number.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "sequence_number")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          sequence_number = req.sequence_number
          if FeatureFlag.vexi.enabled?(:octoshift_experimental_incremental_migrations, repository.owner, default: false)
            # If a batched migration is being performed, Octoshift is likely
            # attempting to set the sequence number to the current batch size,
            # rather than the actual total number of issues in the repo.
            #
            # If this is the first batch import, the sequence number will start at 0, and we should set the sequence to the batch size.
            # If this is a subsequent batch, the migration issue will have already been created, which would have appropriately set the sequence at the highest number (at the time the first batch was run) so we'll leave the number as-is to not overwrite with a lower number.
            current_sequence = ::Sequence.get(repository)

            if current_sequence >= sequence_number
              sequence_number = current_sequence
            end
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            ::Sequence.set(repository, sequence_number)
          end

          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the UpdateActionsSettings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::UpdateActionsSettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::UpdateActionsSettingsResponse, or a Twirp::Error.
        def update_actions_settings(req, env)
          unless req.repository_id.positive?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          if req.actions_permission == :ACTIONS_PERMISSION_TYPE_INVALID
            return Twirp::Error.invalid_argument("must be a valid permission type.", argument: "actions_permission")
          end

          install_actions_app_feature_enabled = repository.owner.feature_flag_enabled?(:octoshift_install_actions_app, default: false)

          if !install_actions_app_feature_enabled
            # For scheduled workflows to run post-migration, launch must be informed
            repository.workflows.select(&:scheduled?).each do |workflow|
              workflow.synchronize_scheduled_workflow_in_launch(repository, repository.owner)
            end
          end

          actions_permission = req.actions_permission
          allows_github_owned_actions = req.allows_github_owned_actions
          allows_verified_actions = req.allows_verified_actions
          patterns = req.patterns

          if req.actions_permission == :ACTIONS_PERMISSION_TYPE_INHERITED
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

          ActiveRecord::Base.connected_to(role: :writing) do
            case actions_permission
            when :ACTIONS_PERMISSION_TYPE_ALL_ENABLED
              repository.enable_actions(actor: repository.owner) if !install_actions_app_feature_enabled
            when :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED
              repository.enable_actions(actor: repository.owner) if !install_actions_app_feature_enabled
              repository.enable_local_actions_only
            when :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
              repository.enable_actions(actor: repository.owner) if !install_actions_app_feature_enabled
              repository.enable_specified_actions_only(actor: repository.owner,
                github_owned: allows_github_owned_actions,
                verified: allows_verified_actions,
                patterns: patterns)
            end

            if install_actions_app_feature_enabled
              case actions_permission
              when :ACTIONS_PERMISSION_TYPE_ALL_ENABLED, :ACTIONS_PERMISSION_TYPE_LOCAL_ENABLED, :ACTIONS_PERMISSION_TYPE_SPECIFIC_ENABLED
                repository.enable_actions(actor: repository.owner)
                unless repository.actions_app_installed?
                  repository.enable_actions_app(actor: repository.owner, entry_point: :twirp_api_octoshift_import_repository_api_handler_install_actions_app)
                end
              end

              # For scheduled workflows to run post-migration, launch must be informed
              repository.workflows.select(&:scheduled?).each do |workflow|
                workflow.synchronize_scheduled_workflow_in_launch(repository, repository.owner)
              end
            end

            unless repository.save
              return Twirp::Error.canceled("Repository actions settings failed to update.")
            end
          end

          {
            repository: build_repository_hash(repository)
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the DeleteRepository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::DeleteRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::DeleteRepositoryResponse, or a Twirp::Error.
        def delete_repository(req, env)
          unless req.repository_id.positive?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          import = repository.import
          unless import
            return Twirp::Error.not_found("Repository was not created by an import", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_NOT_CREATED_BY_IMPORT")
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            repository.remove(import.creator, synchronous: true)
          end
          # since the repository is getting deleted, we should return the current repository variable instead of the reloaded variable

          { repository: build_repository_hash(repository).merge({ is_deleted: true }) }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the CheckIfRepositoryExists Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::CheckIfRepositoryExistsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::CheckIfRepositoryExistsResponse, or a Twirp::Error.
        def check_if_repository_exists(req, env)
          if req.owner_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "owner_id")
          end
          if req.name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end

          owner = replica(User).find_by(id: req.owner_id)
          unless owner
            return Twirp::Error.not_found("Owner not found.", argument: "owner_id", value: req.owner_id.to_s)
          end

          repository = replica(Repository).find_by(name: req.name, owner: owner, active: true)

          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "name", value: req.name)
          end

          {
            repository: build_repository_hash(repository)
          }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def has_octoshift_migrator_role?(actor, target_login)
          Octoshift::AuthorizationPolicy.has_octoshift_migrator_role?(actor, replica(User).find_by(login: target_login))
        end

        def create_empty_wiki(repository, user)
          repository.initialize_wiki(user)
        end

        def update_general_settings(repository, owner, general_settings)
          general_setting_errors = []

          if general_settings.is_template&.value
            unless repository.update(template: general_settings.is_template&.value)
              general_setting_errors << "Repository template setting could not be imported."
            end
          end

          begin
            repository.update_merge_settings(owner,
              merge_allowed: general_settings.has_merge_commit&.value,
              squash_allowed: general_settings.has_squash_merge&.value,
              rebase_allowed: general_settings.has_rebase_merge&.value,
              auto_merge_allowed: general_settings.has_auto_merge&.value
            )
          rescue Repository::PullRequestDependency::MergeMethodError
            general_setting_errors << "Repository merge settings could not be imported because at least one merge setting must be selected. Commit merges were turned on by default."
            repository.update_merge_settings(owner, merge_allowed: true)
          end

          if general_settings.has_update_branch&.value
            repository.update_merge_settings(owner, update_branch_allowed: true)
          end

          if general_settings.has_delete_branch_heads&.value
            repository.allow_auto_deleting_branches(actor: owner)
            general_setting_errors << "Auto deleting branch heads could not be enabled." unless repository.delete_branch_on_merge?
          end

          if repository.private_repository_forking_configurable?
            if owner.allow_private_repository_forking?
              if general_settings.has_allow_forking&.value
                repository.allow_private_repository_forking(actor: owner)
                general_setting_errors << "Forking could not be enabled." unless repository.allow_private_repository_forking?
              else
                repository.block_private_repository_forking(actor: owner)
              end
            else
              if general_settings.has_allow_forking&.value
                general_setting_errors << "'Allow Forking' setting could not be enabled for the repository because it is not enabled at the organization level."
              else
                repository.block_private_repository_forking(actor: owner)
              end
            end
          end

          if general_settings.has_sponsorships&.value
            repository.enable_repository_funding_links(actor: owner)
            general_setting_errors << "Sponsorships could not be enabled." unless repository.repository_funding_links_enabled?
          end

          if general_settings.has_projects&.present?
            begin
              general_settings.has_projects.value ? repository.enable_repository_projects(actor: owner) : repository.disable_repository_projects(actor: owner)
              general_setting_errors << "Projects setting could not be imported." unless repository.projects_enabled? == general_settings.has_projects.value
            rescue Repository::ProjectsDependency::CannotEnableProjectsError
              general_setting_errors << "Projects cannot be enabled when the owning organization/enterprise has projects disabled."
            end
          end

          if general_settings.has_discussions&.value
            repository.turn_on_discussions(actor: owner)
            general_setting_errors << "Discussions could not be enabled." unless repository.discussions_on?
          end

          if general_settings.has_git_lfs_in_archives&.value
            repository.enable_lfs_in_archives(owner)
            general_setting_errors << "LFS in archives could not be enabled." unless repository.lfs_in_archives_enabled?
          end

          general_setting_errors
        end

        def create_webhooks(repository, webhooks_req)
          return [] if Hook.webhooks_for_target(repository).any?

          hooks = []
          webhooks_req.each do |webhook_req|
            hook = Hook.create(
              installation_target: repository,
              name: "web",
              active: webhook_req.active,
              config: {
                "url"          => webhook_req.payload_url,
                "insecure_ssl" => webhook_req.enable_ssl_verification ? "0" : "1",
                "content_type" => webhook_req.content_type,
              },
              events: webhook_req.event_types & valid_repo_event_types,
            )

            hook.save
            hooks << hook
          end

          hooks
        end

        def create_repository_topics(repository, repository_topics)
          repository_topics.each do |topic|
            user = find_mannequin_or_user_by_login(topic.creator_login)
            unless user
              GitHub.logger.info("Could not find user for topic",
                {
                  "gh.migration_tools.repository_topic.creator_login" => topic.creator_login,
                  "gh.migration_tools.repository_topic.name" => topic.topic_name,
                  "gh.repo.id" => repository.id
                })
              next
            end

            if topic.topic_name.blank?
              GitHub.logger.info("Could not create repository topic for invalid topic", "gh.repo.id" => repository.id)
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

            imported_repository_topic = ActiveRecord::Base.connected_to(role: :writing) do
              repository_topic.save
            end

            unless imported_repository_topic
              GitHub.logger.info("Could not save repository topic",
                {
                  "gh.migration_tools.repository_topic.name" => topic.topic_name,
                  "gh.repo.id" => repository.id
                })
              next
            end
          end
        end

        def build_repository_hash(repository, has_wiki = false, page_validation_error = nil, security_setting_errors = [], general_setting_errors = [])
          ssh_url = repository.ssh_url
          http_url = repository.http_url

          wiki = repository.unsullied_wiki if has_wiki
          wiki_ssh_url = Google::Protobuf::StringValue.new(value: wiki.ssh_url) if wiki
          wiki_http_url = Google::Protobuf::StringValue.new(value: wiki.http_url) if wiki

          {
            id: repository.id,
            owner_id: repository.owner.id,
            name: repository.name,
            visibility: get_repository_visibility(repository),
            default_branch: repository.default_branch,
            ssh_push_url: ssh_url,
            http_url: http_url,
            wiki_ssh_url: wiki_ssh_url,
            wiki_http_url: wiki_http_url,
            page_error_message: page_validation_error,
            security_setting_errors: security_setting_errors,
            general_setting_errors: general_setting_errors,
            is_archived: repository.archived?,
            is_deleted: repository.deleted?
          }
        end

        def return_repository_creation_policy_failure_errors?
          FeatureFlag.vexi.enabled_or_raise?(:octoshift_ops__return_repository_creation_policy_failure_errors) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        end
      end
    end
  end
end
