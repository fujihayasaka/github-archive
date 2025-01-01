# typed: false
# frozen_string_literal: true

module Stafftools
  class RemindersBetaSignupController < StafftoolsController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Permissions,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    def index
      memberships = EarlyAccessMembership.
        preload(:member, :actor).
        order("created_at ASC").
        reminders_waitlist.
        paginate(page: current_page, per_page: 100)

      target_ids = memberships.map(&:member_id)

      permitted_app_ids = Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: current_user.id)
      capable_internal_apps = Apps::Privileged::Registry.all_aliases.inject([]) do |result, app_alias|
        app = Apps::Privileged.integration(app_alias)
        if Apps::Privileged.capable?(:access_internal_reminders_api, app: app)
          result << app if app.adminable_by?(current_user) || permitted_app_ids.include?(app.id)
        end
        result
      end

      view = create_view_model(
        Stafftools::RemindersBetaSignup::IndexView,
        memberships: memberships,
        capable_internal_apps: capable_internal_apps,
        slack_installations: installations_by_target(Apps::Privileged.integration(:slack), target_ids: target_ids),
      )
      render "stafftools/reminders_beta_signup/index", locals: { view: view }
    end

    def toggle_reminder_event # rubocop:todo GitHub/UseRestfulActions
      permitted_app_ids = Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: current_user.id)
      integration = Integration.find_by_id(params[:integration_id])
      head :unauthorized and return unless integration.adminable_by?(current_user) || permitted_app_ids.include?(integration.id)
      default_events = integration.default_events
      default_permissions = integration.default_permissions
      updated_events = if default_events.include?("reminder")
        default_events - ["reminder"]
      else
        default_events + ["reminder"]
      end
      result = Integration::PermissionsEditor.perform(
        integration: integration,
        permissions_and_events: { default_events: updated_events, default_permissions: default_permissions }.stringify_keys,
      )
      if result.success?
        head :ok
      else
        render json: result.error, status: :unprocessable_entity
      end
    end

    private

    def installations_by_target(integration, target_ids:)
      installations = IntegrationInstallation.
        preload(integration: :latest_version, target: []).
        where(integration_id: integration.id, target_id: target_ids)

      installations.to_h do |installation|
        [installation.target, installation]
      end
    end
  end
end
