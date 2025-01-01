# typed: true
# frozen_string_literal: true

module PullRequests::UnlistedPrHelper
  # Passing this information to the `PullRequests::StateComponent` allows us to begin showing the "Unlisted" badges
  sig { params(pull_request: T.nilable(PullRequest), current_user: T.nilable(User)).returns(T::Boolean) }
  def is_unlisted_ff_enabled?(pull_request:, current_user:)
    if FeatureFlag.vexi.enabled?(:exclude_copilot_draft_prs_from_search, current_user, default: false)
      !!pull_request&.unlisted?
    else
      false
    end
  end
end
