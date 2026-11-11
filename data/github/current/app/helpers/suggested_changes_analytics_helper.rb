# typed: true
# frozen_string_literal: true

module SuggestedChangesAnalyticsHelper
  include HydroHelper

  def suggested_changes_click(target, user = T.unsafe(self).current_user, pull_request = @pull)
    pull_request_id, relationship = if pull_request
      # In some views pull request is a GraphQL object, in those cases we want to access a hash we pass in instead
      pr_user_id = pull_request.is_a?(Hash) ? pull_request[:user_id] : pull_request.user_id
      global_relay_id = pull_request.is_a?(Hash) ? pull_request[:global_relay_id] : pull_request.global_relay_id

      relationship = pr_user_id == user.id ? "author" : "reviewer"
      [global_relay_id, relationship]
    end

    hydro_attributes = hydro_click_tracking_attributes("suggested_changes.target.click",
      user_id: user.id,
      target_type: target,
      pull_request_id: pull_request_id,
      relationship_to_suggestion: relationship,
    )

    hydro_attributes.merge(
      "ga-click": "Markdown Toolbar, click, insert code suggestion",
    )
  end
end
