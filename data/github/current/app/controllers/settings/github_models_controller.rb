# typed: true
# frozen_string_literal: true

class Settings::GitHubModelsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :require_feature
  before_action :github_models_required
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  def index
    render "settings/github_models/index", locals: {}
  end

  private

  def require_feature
    return if user_feature_enabled?(:github_models_billing_ui)

    render_404
  end

end
