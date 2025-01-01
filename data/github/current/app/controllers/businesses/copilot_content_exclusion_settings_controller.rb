# typed: strict
# frozen_string_literal: true

class Businesses::CopilotContentExclusionSettingsController < Businesses::BusinessController
  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :ensure_copilot_policies_page_refresh_enabled

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

  sig { void }
  def index
    render_index
  end

  private

  sig { returns(T.untyped) }
  def content_exclusions_partial_payload
    config = Copilot::ContentExclusionConfiguration.for_business(this_business).first

    # Keep types in sync with ui/packages/copilot-content-exclusion/partials/IgnoreForm.tsx#Payload
    {
      endpoint: update_settings_copilot_content_exclusion_enterprise_path(this_business),
      lastEdited: config&.updated_by ? { login: config.updated_by&.display_login, time: config.updated_at, link: content_exclusions_audit_link } : nil,
      document: config&.document,
    }
  end

  sig { returns(String) }
  def content_exclusions_audit_link
    query = Search::Queries::AuditLogQuery.stringify(["action:#{Copilot::Events::COPILOT_FOR_BUSINESS_CONTENT_EXCLUSION_CHANGED}"])
    settings_audit_log_enterprise_path(this_business, q: query)
  end

  sig { params(error: T.nilable(String)).void }
  def render_index(error: nil)
    render "businesses/copilot_settings/content_exclusion/index", locals: {
      title: "Content exclusion",
      error: error,
      content_exclusions_partial_payload:
    }
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
  def ensure_copilot_policies_page_refresh_enabled
    render_404 unless this_business.feature_enabled?(:enterprise_copilot_policies_refresh)
  end

end
