# typed: strict
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  module Creators
    class CodespaceWithOauthAccess < ScopedIntegrationInstallation::Creators::Base

      include ScopedIntegrationInstallation::PermissionRowsGenerator
      include CodespaceAuthorizationDetailsWriter

      STATS_KEY = "site_scoped_integration_installation.creators.codespace_with_oauth_access"

      sig do
        params(
          codespace: Codespace,
          oauth_access: OauthAccess,
          entry_point: T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint),
          devcontainer: T.nilable(::Codespaces::DevContainer)
        ).returns(::ScopedIntegrationInstallation::Result)
      end
      def self.perform(codespace:, oauth_access:, entry_point: nil, devcontainer: nil)
        new(codespace:, oauth_access:, entry_point:, devcontainer:).perform
      end

      sig { returns(Integration) }
      attr_reader :integration

      sig { returns(InstallationTarget) }
      attr_reader :target

      sig do
        params(
          codespace: Codespace,
          oauth_access: OauthAccess,
          entry_point: T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint),
          devcontainer: T.nilable(::Codespaces::DevContainer)
        ).void
      end
      def initialize(codespace:, oauth_access:, entry_point: nil, devcontainer: nil)
        @codespace    = codespace
        @oauth_access = oauth_access
        @entry_point  = entry_point

        @codespace_repository = T.let(T.cast(@codespace.repository, Repository), Repository) # rubocop:todo GitHub/AvoidCast
        @devcontainer         = devcontainer
        @integration          = T.let(T.must(@oauth_access.integration), Integration)
        @permissions          = T.let(@integration.default_permissions, T::Hash[String, Symbol])
        @target               = T.let(T.must(@codespace_repository.owner), T.any(Organization, User))
        @user                 = T.let(T.cast(@oauth_access.user, User), User)

        @elevated_read_access_integration_installation = T.let(nil, T.nilable(IntegrationInstallation))

        @installation = T.let(build_installation, SiteScopedIntegrationInstallation)
        @authorization_details = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
      end

      sig { returns(::ScopedIntegrationInstallation::Result) }
      def perform
        validate_permissions!

        # Build all of the permission rows with the not yet persisted
        # installation.
        permission_rows_per_target = synthesize_permission_rows!
        @installation.authorization_details = synthesize_authorization_details!(permission_rows_per_target)

        @installation.save!
        @oauth_access.update!(installation: @installation)

        # Update the oauth access with the installation.
        @oauth_access.reload

        # Sets the expiration for the access and the installation without
        # needing to update all of the `permissions` rows.
        token, _ = @oauth_access.redeem(extended_expiry: true)

        # Get the installation with the updated expires_at.
        @installation.reload

        # Register the association to the Codespace.
        codespace_resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Codespace
        grants_any_codespace_permissions = @installation.authorization_details_struct.granted_subject_ids_for(codespace_resource_type).present?

        CodespacesSiteScopedIntegrationInstallation.create!(
          codespace: @codespace,
          site_scoped_integration_installation: @installation
        ) if grants_any_codespace_permissions

        result = ::ScopedIntegrationInstallation::Result.success(@installation)
        result.credential = token

        result
      rescue ActiveRecord::ActiveRecordError,
        ScopedIntegrationInstallation::Result::Error,
        KeyError,
        JSON::Schema::ValidationError => e
        @oauth_access.destroy
        @installation.destroy

        log_permissions_error_details(e)

        ::ScopedIntegrationInstallation::Result.failed(error_message_for_exception(e))
      end

      private

      sig do
        params(
          entry_point: T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint),
          target: InstallationTarget
        ).returns(T.any(NilClass, Symbol, ::Permissions::Service::EntryPoint))
      end
      def build_entry_point_for_target(entry_point, target)
        return nil if entry_point.nil?

        tag = entry_point.is_a?(Symbol) ? entry_point : entry_point.entry_point
        ::Permissions::Service::EntryPoint.build(tag, target: target, actor_owner: @integration)
      end

      sig { returns(SiteScopedIntegrationInstallation) }
      def build_installation
        SiteScopedIntegrationInstallation.new(integration: @integration, target: @target)
      end

      # Override the default expiration window for Codespaces.
      # The expiration is custom set from the OauthAccess.
      sig { returns(FalseClass) }
      def expires?
        false
      end

      sig { returns(T::Boolean) }
      def grant_access_to_dotfiles_repository?
        @user.codespace_dotfiles_enabled? && @user.codespace_dotfiles_repository.present?
      end

      sig { returns(T::Array[PermissionRow]) }
      def grant_default_access
        permission_rows_for_subjects(
          actor: @installation,
          subjects: [@codespace_repository],
          permissions: repository_permissions
        )
      end

      sig { returns(T::Array[PermissionRow]) }
      def grant_dotfiles_access
        return [] unless grant_access_to_dotfiles_repository?

        dotfiles_repo = @user.codespace_dotfiles_repository
        return [] if dotfiles_repo.id == @codespace_repository.id # No extra permission needed for the same repo.

        unless Apps::Privileged.repo_accessible_to_limited_app?(dotfiles_repo, app: @integration)
          raise_error "This integration doesn't have access to the user's dotfiles repository."
        end

        # Grant basic read permission to the dotfiles repository.
        permission_rows_for_subjects(actor: @installation, subjects: [dotfiles_repo], permissions: {
          "metadata" => :read, "contents" => :read
        })
      end

      sig { returns(T::Array[PermissionRow]) }
      def grant_devcontainer_permissions
        rows = []

        if @devcontainer&.all_repository_permissions.present?
          diff_permissions = @devcontainer&.diff_all_repository_permissions

          # If the devcontainer has consented to permissions on the target,
          # we should grant those permissions.
          if diff_permissions.consented.any?
            diff_permissions.consented[@target].each do |resource, action|
              subject = @target.repository_resources.public_send(resource) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
              rows << permission_row_for(actor: @installation, subject: subject, action: action)
            end
          end
        end

        diff_permissions = @devcontainer&.diff_repository_permissions
        consented = diff_permissions&.consented || {}

        # If the @codespace_repository is not in the consented permissions,
        # add it to the list so it gets granted access.
        if consented.key?(@codespace_repository)
          # Merge the two sets of permissions and take the highest action is necessary.
          # This allows all of the necessary permissions to be written.
          consented[@codespace_repository].merge!(repository_permissions) do |_resource, action, default_action|
            consented_action = T.must(Permission.actions[action])
            default_action = T.must(Permission.actions[default_action])

            [consented_action, default_action].max
          end
        else
          consented[@codespace_repository] = repository_permissions
        end

        consented.each do |repo, permissions|
          unless Apps::Privileged.repo_accessible_to_limited_app?(repo, app: @integration)
            raise_error "This integration doesn't have access to all of the requested repositories"
          end

          rows.concat(permission_rows_for_subjects(actor: @installation, subjects: [repo], permissions: permissions))
        end

        rows
      end

      sig { returns(T::Boolean) }
      memoize def grant_devcontainer_permissions?
        return false unless Apps::Privileged.capable?(:upgrade_default_permissions, app: @integration)

        @devcontainer.present? && @devcontainer.has_custom_permissions?
      rescue Codespaces::DevContainer::ReadError
        false
      end

      sig { returns(T::Boolean) }
      def grant_elevated_read_access?
        return false unless Apps::Privileged.capable?(:elevated_read_access_on_target, app: @integration)

        if ::Codespaces::Tokens.request_elevated_read_access?(@codespace) && !grant_devcontainer_permissions?
          @elevated_read_access_integration_installation = IntegrationInstallation.find_by(
            integration: @integration,
            target: @target
          )

          return @elevated_read_access_integration_installation.present?
        end

        false
      end

      sig { returns(T::Array[PermissionRow]) }
      def grant_elevated_read_access
        rows = []

        # Grant all repo permissions as 'read' on the target.
        readonly_permissions = repository_permissions.transform_values { :read }

        readonly_permissions.each do |resource, action|
          subject = @target.repository_resources.public_send(resource) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          rows << permission_row_for(actor: @installation, subject: subject, action: action)
        end

        # Find all of permissions greater than 'read' and apply it to the
        # codespace repository.
        repository_permissions.each do |resource, action|
          next if T.must(Permission.actions[action]) <= T.must(Permission.actions[:read])

          subject = @codespace_repository.resources.public_send(resource) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          rows << permission_row_for(actor: @installation, subject: subject, action: action)
        end

        rows
      end

      sig { returns(T::Array[PermissionRow]) }
      def grant_fork_access
        return [] unless @codespace_repository.fork?

        parent_repository = @codespace_repository.parent

        unless Apps::Privileged.repo_accessible_to_limited_app?(parent_repository, app: @integration)
          raise_error "This integration doesn't have access to the fork's parent repository."
        end

        return [] if parent_repository.nil?

        fork_permissions = {
          "pull_requests_from_forks" => :write,
          "pull_requests_comment_only_reviews" => :write
        }

        grantable_permissions = @codespace_repository.private? ? repository_permissions : fork_permissions

        permission_rows_for_subjects(actor: @installation, subjects: [parent_repository], permissions: grantable_permissions)
      end

      sig { returns(T::Hash[String, Symbol]) }
      memoize def repository_permissions
        Repository::Resources.filter(@permissions)
      end

      sig { returns(T::Hash[InstallationTarget, T::Array[PermissionRow]]) }
      def synthesize_permission_rows!
        rows = []

        # Attempt to grant package permissions first so that we don't try to
        # synthesize the rest in vain.
        rows.concat(
          generate_and_validate_permission_rows_for_packages!(
            integration: @integration,
            installation: @installation,
            target: @target,
            repositories: [@codespace_repository],
            permissions: @permissions,
          )
        )

        # Include permission rows for the codespace.
        rows.concat(
          permission_rows_for_codespaces(
            integration: @integration,
            installation: @installation,
            codespaces: [@codespace],
          )
        )

        # Include organization permissions for the target.
        rows.concat(
          permission_rows_for_subjects(
            actor: @installation,
            subjects: [@target],
            permissions: organization_permissions(@permissions)
          )
        )

        # All permissions up to this point are related to the same target.
        rows_per_target = {
          target => rows
        }

        # Include repository permissions that can include permissions on
        # the parent repository and the user's dotfiles repository.
        # In the case of a fork, repository the target is the owner of the
        # parent repository which can be different from @target.
        rows_from_repositories = synthesize_repository_permissions
        rows_from_repositories.each do |target, rows|
          rows_per_target[target] = rows_per_target.fetch(target, []) | rows
        end

        rows_per_target
      end

      sig { returns(T::Hash[InstallationTarget, T::Array[PermissionRow]]) }
      def synthesize_repository_permissions
        rows = []

        rows =
          if grant_elevated_read_access?
            grant_elevated_read_access
          elsif grant_devcontainer_permissions?
            grant_devcontainer_permissions
          else
            grant_default_access
          end

        rows_per_target = {
          target => rows
        }

        if Apps::Privileged.capable?(:integration_installation_multiple_target_permissions, app: @integration)
          rows_from_parent_repo = grant_fork_access
          if rows_from_parent_repo.present?
            parent_repo_owner = T.must(@codespace_repository.parent).owner
            rows_per_target[parent_repo_owner] = rows_per_target.fetch(parent_repo_owner, []) + rows_from_parent_repo
          end

          rows_from_dotfiles = grant_dotfiles_access
          if rows_from_dotfiles.present?
            rows_per_target[@user] = rows_per_target.fetch(@user, []) + rows_from_dotfiles
          end
        end

        rows_per_target
      end

      sig { void }
      def validate_app_capability!
        unless Apps::Privileged.capable?(:installed_globally, app: @integration)
          raise_error "Integration can't be globally installed"
        end

        if @integration.feature_enabled?(:disabled_global_apps)
          raise_error "Global-Apps is disabled for this integration"
        end
      end

      sig { void }
      def validate_target_accessibility!
        unless Apps::Privileged.target_accessible_to_limited_app?(@target, app: @integration)
          raise_error "This integration doesn't have access to the given target"
        end
      end

      sig { void }
      def validate_permissions!
        validate_app_capability!
        validate_target_accessibility!
      end
    end
  end
end
