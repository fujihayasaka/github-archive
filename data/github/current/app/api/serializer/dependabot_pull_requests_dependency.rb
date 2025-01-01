# typed: true
# frozen_string_literal: true

module Api::Serializer::DependabotPullRequestsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  def dependabot_twirp_pull_request_hash(data, options = {})
    pull_request = data[:pull_request]
    return nil if pull_request.blank?

    {
      github_number: pull_request.number,
      repository_id: pull_request.repository_id,
      head_sha: pull_request.head_sha,
      head_ref: pull_request.head_ref,
      base_sha: pull_request.base_sha,
      base_ref: pull_request.base_ref,
      state: pull_request.state.to_s,
      has_user_commits: data.fetch(:has_user_commits, false)
    }
  end
end
