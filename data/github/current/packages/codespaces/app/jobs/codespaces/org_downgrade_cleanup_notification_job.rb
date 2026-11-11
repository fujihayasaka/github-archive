# typed: true
# frozen_string_literal: true

class Codespaces::OrgDowngradeCleanupNotificationJob < CodespacesJob
  retry_on_dirty_exit

  def perform(owner_id:, deletion_date:)
    owner = Organization.find_by(id: owner_id)
    return unless owner && owner.organization?
    return unless Codespaces::OrgPolicy.new(org: owner, user: nil).must_upgrade_to_use_codespaces?
    codespaces_count = Codespace.where(billable_owner: owner).count
    return unless codespaces_count > 0

    owner.admins.each do |admin|
      CodespacesOrgDowngradedMailer.downgraded(admin, owner, codespaces_count, deletion_date).deliver_later
    end
  end
end
