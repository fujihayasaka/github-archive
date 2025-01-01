# typed: true
# frozen_string_literal: true

class DeliverIntegrationUpdateEmailJob < ApplicationJob
  queue_as :deliver_integration_update_email
  discard_on ActiveRecord::RecordNotFound
  retry_on_dirty_exit

  def perform(installation_id, integration_version_id: nil)
    installation = IntegrationInstallation.find(installation_id)

    integration = T.must(installation.integration)
    target      = installation.target

    target.admins.each do |admin|
      IntegrationMailer.updated_permissions(installation, recipient: admin).deliver_now
    end

    # If the installation can be updated by repo admins, find those admins
    # and email them as well.
    return unless target.organization?
    return unless integration.repository_permissions_only?

    # If the installation is installed on all, we don't want
    # to calculate if there are any repo admins that _could_
    # manage all of them.
    #
    # Too expensive.
    return if installation.installed_on_all_repositories?

    repo_admin_ids = Array(installation.repositories.map do |repo|
      repo.user_ids_with_privileged_access(min_action: :admin)
    end.reduce(:&))

    repo_admin_ids = repo_admin_ids - target.admins.pluck(:id)
    return if repo_admin_ids.empty?

    repo_admins = User.where(id: repo_admin_ids).to_a

    # The IntegrationVersion KWARG is optional until we get a full
    # deployment out.
    if (version = IntegrationVersion.find_by(id: integration_version_id))
      repo_admins.keep_if do |admin|
        IntegrationInstallation::Permissions.check(
          installation: installation, actor: admin, action: :update_permissions, version: version
        ).permitted?
      end
    end

    repo_admins.each do |admin|
      IntegrationMailer.updated_permissions_repo_adminable(installation, recipient: admin).deliver_now
    end
  end
end
