# typed: true
# frozen_string_literal: true

# Returns cache-dependent payload fields for the embedded immersive panel.
# Called asynchronously after the panel opens to avoid hitting
# the Copilot user cache on every page load.
class Copilot::Chat::DeferredPayloadsController < Copilot::Chat::AbstractChatController
  depends_on_clusters(
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    only: [:show],
  )

  def show
    render json: immersive_chat_deferred_payload
  end

  private

  def feature_enabled?
    true
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def target_for_conditional_access
    return current_user if logged_in?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
