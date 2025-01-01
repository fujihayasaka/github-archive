# typed: strict
# frozen_string_literal: true

class Billing::CopilotModelsController < ApplicationController
  before_action :ensure_billing_enabled, :login_required

  include Billing::ModelsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:index]

  sig { void }
  def index
    render_models_data
  end

  private

  sig { returns(T.any(User, Symbol)) }
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
