# typed: true
# frozen_string_literal: true

class GitHubConnectDestroyInstallationContributionsJob < ApplicationJob
  queue_as :github_connect

  def perform(installation_id)
    return if GitHub.enterprise?

    with_write { EnterpriseContribution.clear_installation_contributions!(installation_id) }
  end
end
