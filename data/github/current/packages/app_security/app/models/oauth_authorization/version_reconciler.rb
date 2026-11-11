# typed: true
# frozen_string_literal: true

class OauthAuthorization
  class VersionReconciler
    attr_reader :entry_point

    def initialize(authorization, user:, entry_point:, integration_version_context:)
      @authorization = authorization
      @user = user
      @entry_point = entry_point
      @version_context = integration_version_context
    end

    # Public: Reconcile the authorization's integration version.
    # Resolves the target version, diffs if outdated, and updates permissions accordingly.
    #
    # This method may be called within the authorization's transaction.
    def perform
      return unless @authorization.integration_application_type? && @version_context.present?

      # An empty version context means there is nothing to reconcile.
      # This can occur when build_integration_version_context returns {} for
      # non-integration applications or integrations with no versions.
      return if @version_context.blank?

      current_version = @version_context[:current_version]
      resolved_version = resolve_version_from_context

      if @authorization.integration_version_number.present? && \
          (current_version.number < resolved_version.number)
        diff = IntegrationVersion::Differ.perform(old_version: current_version, new_version: resolved_version)
        update_integration_version(resolved_version, diff)
      else
        set_integration_version(resolved_version)
      end
    end

    private

    def resolve_version_from_context
      current_version = @version_context[:current_version]
      target_version = @version_context[:target_version]
      latest_version = @version_context[:latest_version]

      # Prevent version downgrading
      if (@authorization.integration_version_number == current_version.number) && (target_version.number < current_version.number)
        latest_version
      else
        # Try to use the user-requested version number, or fallback to the
        # latest version for the App.
        target_version
      end
    end

    def set_integration_version(version)
      add_user_permissions(permissions: version.user_permissions)
      @authorization.update!(integration_version_number: version.number)
    end

    def update_integration_version(version, diff)
      add_user_permissions       permissions: diff.permissions_added      if diff.permissions_added?
      upgrade_user_permissions   permissions: diff.permissions_upgraded   if diff.permissions_upgraded?
      downgrade_user_permissions permissions: diff.permissions_downgraded if diff.permissions_downgraded?
      remove_user_permissions    permissions: diff.permissions_removed    if diff.permissions_removed?

      @authorization.update!(integration_version_number: version.number)
    end

    def add_user_permissions(permissions:)
      return if always_use_latest_integration_version?
      rows = []

      permissions.each_pair do |resource, action|
        next unless User::Resources.subject_types.include?(resource)
        subject = @user.resources.public_send(resource.to_s) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

        rows << Permissions::Service.app_attributes(
          actor: @authorization, subject: subject, action: action
        )
      end

      Permissions::Service.grant_permissions(rows, entry_point: entry_point)
    end

    def upgrade_user_permissions(permissions:)
      return if always_use_latest_integration_version?
      subject_types = User::Resources.all_prefixed_subject_types(permissions)
      return if subject_types.empty?

      Permissions::Service.update_action_for_permissions(
        actor_ids: [@authorization.ability_id],
        actor_type: @authorization.ability_type,
        subject_types: subject_types,
        action: :write,
        entry_point: entry_point
      )
    end

    def downgrade_user_permissions(permissions:)
      return if always_use_latest_integration_version?
      subject_types = User::Resources.all_prefixed_subject_types(permissions)
      return if subject_types.empty?

      Permissions::Service.update_action_for_permissions(
        actor_ids: [@authorization.ability_id],
        actor_type: @authorization.ability_type,
        subject_types: subject_types,
        action: :read,
        entry_point: entry_point
      )
    end

    def remove_user_permissions(permissions:)
      subject_types = User::Resources.all_prefixed_subject_types(permissions)
      return if subject_types.empty?

      Permissions::Service.revoke_permissions_granted_on_actor(
        actor_id: @authorization.ability_id,
        actor_type: @authorization.ability_type,
        subject_types: subject_types,
        entry_point: entry_point
      )
    end

    def always_use_latest_integration_version?
      ::Apps::Privileged.capable?(:user_permissions_always_uses_latest_version, app: @authorization.application)
    end
  end
end
