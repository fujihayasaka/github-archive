# typed: true
# frozen_string_literal: true

class Spark::EntitlementsController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Configurations,
  ApplicationRecord::Copilot,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Ballast, # temporary, for free cca experiment

  def show
    render json: Workbench::Entitlements.new(T.must(current_user)).to_h
  end

  private

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
