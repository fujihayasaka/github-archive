# typed: true
# frozen_string_literal: true

class GitHubConnectDestroyUserContributionsJob < ApplicationJob
  queue_as :github_connect

  def perform(user, installation_id)
    return if GitHub.enterprise?

    with_write { EnterpriseContribution.clear_user_contributions!(user, installation_id) }
  end
end
