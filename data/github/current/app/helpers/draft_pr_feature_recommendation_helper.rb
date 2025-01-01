# typed: strict
# frozen_string_literal: true

module DraftPrFeatureRecommendationHelper
  extend T::Sig

  include FeatureFlagHelper
  include MemberFeatureRequestsHelper

  sig { params(repository: Repository).returns(T::Boolean) }
  def show_draft_pr_feature_recommendation?(repository)
    owner = repository.owner
    # https://github.com/github/app-partitioning/issues/53
    current_user = T.unsafe(self).current_user

    return false if !owner
    return current_user == owner if owner.user?
    return false unless eligible_for_upsell?(
      feature: MemberFeatureRequest::Feature::DraftPullRequests,
      requester: current_user,
      repo: repository
    )

    true
  end
end
