# typed: true
# frozen_string_literal: true

class NotifyAuthorCommunityAdvisoriesContributionJob < ApplicationJob
  queue_as :community_advisories
  retry_on_dirty_exit

  def perform(pull_request, advisory, publisher_login)
    return if publisher_login.blank?

    comment = "Hi there @#{publisher_login}! A community member has suggested an improvement to " \
              "your security advisory. If approved, this change will affect the " \
              "[global advisory](#{advisory.permalink}) listed at github.com/advisories. It will not affect the " \
              "[version listed in your project repository](#{advisory.repository_advisory.permalink}).\n\nThis " \
              "change will be reviewed by our Security Curation Team. If you have thoughts or feedback, " \
              "please share them in a comment here! If this PR has already been closed, you can " \
              "[start a new community contribution for this advisory](#{advisory.permalink}/improve)"
    org = Organization.find_by(login: GitHub.trusted_oauth_apps_org_name)

    with_write do
      pull_request.issue.comments.create!(
        user: org,
        body: comment,
      )
    end
  end
end
