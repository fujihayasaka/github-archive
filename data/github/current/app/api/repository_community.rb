# typed: true
# frozen_string_literal: true

class Api::RepositoryCommunity < Api::App
  include FeatureFlagHelper

  before do
    deliver_error!(404) unless GitHub.community_profile_enabled?
  end

  # Access community health data for a repository
  get "/repositories/:repository_id/community/profile", operation_id: "repos/get-community-profile-metrics" do
    repo = find_repo!

    deliver_error!(404) if repo.fork?
    deliver_error!(404) if !repo.public? && !feature_enabled_for_current_user?(feature_name: :view_community_profile)

    control_access :view_community_profile,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    community_profile = CommunityProfile.where(repository_id: repo.id).includes(:repository).first
    community_profile ||= CommunityProfile.new(repository: repo)
    deliver :community_profile_hash, community_profile
  end
end
