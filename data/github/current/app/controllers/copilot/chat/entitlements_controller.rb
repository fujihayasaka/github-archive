# typed: true
# frozen_string_literal: true

class Copilot::Chat::EntitlementsController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Copilot,
  ApplicationRecord::IamAbilities,

  def show
    result = { licenseType: helpers.license_type }
    quotas = helpers.limited_user_quotas
    result[:quotas] = quotas if quotas
    render json: result
  end

  private

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
