# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpaces::MenuActionsController < Copilot::Chat::AbstractChatController

  allow_verified_fetch only: [:index]
  before_action :require_xhr
  before_action :require_copilot_spaces_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,

  # Returns permission and metadata for a specific copilot space.
  # This endpoint is part of a performance optimization to move permission checks
  # (editable, adminable) from the main index endpoint to individual space lookups.
  # When the :copilot_spaces_server_side_menu_actions_backend feature flag is enabled,
  # the client calls this endpoint to fetch these details on-demand.
  def index
    copilot_space = if FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, current_user, default: false)
      CopilotSpace.for_owner_login_and_number_with_user_roles!(params[:owner], params[:number])
    else
      CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
    end

    return render_404 unless copilot_space.readable_by?(current_user)

    assign_user_and_cap(copilot_space)
    payload = {
        visibility: copilot_space.visibility,
        shareable: copilot_space.shareable?,
        editable:  copilot_space.async_editable_by?(current_user).sync,
        adminable: copilot_space.async_adminable_by?(current_user).sync,
        baseRole: copilot_space.base_role,
        public: copilot_space.public?,
    }
    render json: payload
  end

  private

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
