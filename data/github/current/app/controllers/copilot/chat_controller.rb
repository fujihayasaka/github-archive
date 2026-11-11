# typed: true
# frozen_string_literal: true

class Copilot::ChatController < Copilot::Chat::AbstractChatController
  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:show],
  )

  def show
    user = T.must(current_user)
    if user.feature_flag_enabled?(:copilot_immersive_embedded_deferred_payload, default: false)
      payload = {
        **immersive_chat_payload_lite,
        deferredPayloadUrl: copilot_chat_deferred_payload_path(format: :json),
        agentQuotaSnapshot: helpers.agent_quota_snapshot_for_user(user),
      }
    else
      payload = {
        **immersive_chat_payload,
      }
    end
    respond_to do |format|
      format.html do
        render partial: "copilot/chat_show", locals: {
          props: payload
        }
      end
      format.json do
        render json: payload
      end
    end
  end

  private

  def feature_enabled?
    true
  end

  memoize def current_repository
    return unless referring_params[:user_id] && referring_params[:repository]
    repo = Repository.with_name_with_owner(referring_params[:user_id], referring_params[:repository])
    cap_filter.authorized_resources(repo).first
  end

  # current_repository is not required but used in the CAP filter if given
  def resource_for_conditional_access
    return current_repository if current_repository
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return current_repository.owner if current_repository
    return current_user if logged_in?
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
