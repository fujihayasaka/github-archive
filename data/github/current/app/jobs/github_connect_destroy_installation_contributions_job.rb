# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitHubConnectDestroyInstallationContributionsJob < ApplicationJob
  queue_as :github_connect

  resolve_tenant_context do |installation_id|
    installation = EnterpriseInstallation.find_by(id: installation_id)
    owner = installation&.owner
    if owner.is_a?(Business)
      owner
    elsif owner.is_a?(Organization)
      owner.business
    else
      nil
    end
  end

  def perform(installation_id)
    return if GitHub.enterprise?

    with_write { EnterpriseContribution.clear_installation_contributions!(installation_id) }
  end
end
