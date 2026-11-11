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
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    only: [:index]

  def index
    payload = {
      owners: [],
    }

    filtered_owners.each do |owner|
      payload[:owners] << {
        name: owner.display_login,
        avatarUrl: owner.primary_avatar_url,
        displayName: owner.profile_name || owner.display_login,
        type: owner.type,
        id: owner.id,
        allowsPrivateReposFromOtherOrgs: FeatureFlag.vexi.enabled?(:copilot_spaces_allow_repos_from_other_orgs, owner, default: false)
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

  # Returns the list of owners and authorized orgs
  # If no `repo_id` is provided, we return all authorized orgs for the user that have copilot enabled
  # If a `repo_id` is provided and repo is not public, limit authorized orgs to org that owns the repo
  def filtered_owners
    # If individual access is disabled (behind feature flag), do not include the user as a possible owner
    owners =
      if FeatureFlag.vexi.enabled?(:copilot_spaces_block_individual_access, current_user, default: false)
        individual_access_enabled = Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(current_user)) == "enabled"
        individual_access_enabled ? [current_user] : []
      else
        [current_user]
      end

    authorized_orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs(current_user, cap_filter)

    orgs_to_add = if params[:repo_id].present?
      repo = Repository.find_by(id: params[:repo_id])

      if repo && repo.visibility != "public" && repo.readable_by?(current_user)
        authorized_orgs.select { |org| org.id == repo.organization_id }
      else
        authorized_orgs
      end
    else
      authorized_orgs
    end

    owners + orgs_to_add
  end
end
