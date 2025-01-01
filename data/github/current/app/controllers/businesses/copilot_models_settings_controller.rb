# typed: strict
# frozen_string_literal: true

class Businesses::CopilotModelsSettingsController < Businesses::BusinessController
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

  sig { params(error: T.nilable(String)).void }
  def render_index(error: nil)
    render "businesses/copilot_settings/models/index", locals: {
      copilot_business: copilot_business,
      title: "Models",
      error: error,
      copilot_custom_models: this_business.feature_flag_enabled?(:copilot_custom_models, default: false),
      features_for_data_retention: get_features_for_data_retention,
    }
  end

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { void }
  def ensure_copilot_policies_page_refresh_enabled
    render_404 unless this_business.feature_flag_enabled?(:enterprise_copilot_policies_refresh, default: false)
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end

  sig { returns(String) }
  def get_features_for_data_retention
    return "" unless copilot_business.copilot_plan_business?

    features = []
    features << Copilot::CLI_UI_NAME
    features << Copilot::COPILOT_IN_DOTCOM if copilot_business.has_copilot_enterprise_access? && !standalone_business?
    features << Copilot::COPILOT_CHAT_IN_MOBILE

    return "Enabling #{features.to_sentence} will collect additional data" if !features.empty?
    ""
  end

  sig { returns(T::Boolean) }
  def standalone_business?
    copilot_business.copilot_standalone?
  end
end
