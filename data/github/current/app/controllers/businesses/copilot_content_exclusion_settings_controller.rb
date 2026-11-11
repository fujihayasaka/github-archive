# typed: strict
# frozen_string_literal: true

class Businesses::CopilotContentExclusionSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :business_owner_required, except: [:index, :update]
  before_action :ai_controls_read_access_required, only: [:index]
  before_action :ai_controls_write_access_required, only: [:update]
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled, only: [:index]
  before_action :parse_json_params, only: [:update]

  javascript_bundle :copilot

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  allow_verified_fetch only: [:update]

  sig { void }
  def index
    render_index
  end

  sig { void }
  def update
    new_paths = params[:paths]
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first

    if config.present?
      GitHub.logger.info("Updating ContentExclusionConfiguration", "gh.business.id" => this_business.id, "gh.copilot_ignore_config.id" => config.id)
      config.update(document: new_paths, updated_by: current_user)
    else
      GitHub.logger.info("Creating ContentExclusionConfiguration", "gh.business.id" => this_business.id)
      config = Copilot::ContentExclusionConfiguration.create(
        resource: this_business,
        updated_by: current_user,
        resource_type: "Business",
        document: new_paths
      )
    end

    if new_paths.empty?
      GitHub.logger.info("Setting ContentExclusionConfiguration to blank for business", "gh.business.id" => this_business.id, "gh.user.id" => current_user.id)
    end

    if config.valid?
      payload = {
        message: "Successfully updated the excluded paths",
        lastEdited: {
          login: current_user&.display_login,
          time: config.updated_at,
          link: content_exclusions_audit_link
        }
      }

      render json: payload
    else
      render json: { message: config.errors.first.message }, status: :unprocessable_entity
    end
  end

  private

  sig { returns(T.untyped) }
  def content_exclusions_partial_payload
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first
    can_write = this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false

    # Keep types in sync with ui/packages/copilot-content-exclusion/partials/IgnoreForm.tsx#Payload
    {
      endpoint: update_settings_copilot_content_exclusion_enterprise_path(this_business),
      lastEdited: config&.updated_by ? { login: config.updated_by&.display_login, time: config.updated_at, link: content_exclusions_audit_link } : nil,
      document: config&.document,
      canWrite: can_write,
    }
  end

  sig { returns(String) }
  def content_exclusions_audit_link
    query = Search::Queries::AuditLogQuery.stringify(["action:#{Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED}"])
    settings_audit_log_enterprise_path(this_business, q: query)
  end

  sig { params(error: T.nilable(String)).void }
  def render_index(error: nil)
    can_write = this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false
    is_admin = this_business&.adminable_by?(current_user) || false

    if helpers.show_ai_controls?(this_business)
      render "businesses/ai_controls/copilot/content_exclusion/index", locals: {
        title: "Content exclusion",
        error: error,
        content_exclusions_partial_payload:,
        can_write:,
        is_admin:
      }
    else
      render "businesses/copilot_settings/content_exclusion/index", locals: {
        title: "Content exclusion",
        error: error,
        content_exclusions_partial_payload:,
        can_write:,
        is_admin:
      }
    end
  end

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end

  sig { void }
  def ai_controls_read_access_required
    if helpers.show_ai_controls?(this_business) && FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
      # Use fine-grained AI controls permissions
      render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
    else
      # Fall back to business owner requirement
      business_owner_required
    end
  end

  sig { void }
  def ai_controls_write_access_required
    if helpers.show_ai_controls?(this_business) && FeatureFlag.vexi.enabled?(:enterprise_ai_controls_fine_grained_permissions, this_business, default: false)
      # Use fine-grained AI controls permissions
      render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
    else
      # Fall back to business owner requirement
      business_owner_required
    end
  end
end
