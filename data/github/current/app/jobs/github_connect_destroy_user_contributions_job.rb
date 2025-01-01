# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class GitHubConnectDestroyUserContributionsJob < ApplicationJob
  queue_as :github_connect
  retry_on_dirty_exit

  resolve_tenant_context do |user|
    user.enterprise_managed_business
  end

  def perform(user, installation_id)
    return if GitHub.enterprise?

    with_write { EnterpriseContribution.clear_user_contributions!(user, installation_id) }
  end
end
