# typed: true
# frozen_string_literal: true

class Copilot::Chat::CopilotSpacesOwnersController < Copilot::Chat::AbstractChatController

  allow_verified_fetch only: [:index]
  before_action :require_copilot_spaces_feature_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    payload = {
      owners: [],
    }

    display_name = current_user.display_login
    if current_user.profile_name.present?
      display_name = current_user.profile_name
    end

    owners = [current_user]

    if user_feature_enabled?(:copilot_custom_copilots_org_owned)
      authorized_orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs_with_copilot_access(current_user, cap_filter)
      owners = owners + authorized_orgs
    end

    owners.each do |owner|
      payload[:owners] << {
        name: owner.display_login,
        avatarUrl: owner.primary_avatar_url,
        displayName: owner.profile_name || owner.display_login,
        type: owner.type,
        id: owner.id
      }
    end

    render json: payload
  end

  private

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
