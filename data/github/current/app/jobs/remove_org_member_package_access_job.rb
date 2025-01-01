# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Removes granular permissions for a removed org member from the orgs packages
class RemoveOrgMemberPackageAccessJob < ApplicationJob
  queue_as :remove_org_member_package_access

  retry_on_dirty_exit

  BATCH_SIZE = 100

  retry_on(PackageRegistry::Twirp::BaseError, wait: 5.seconds, attempts: 10) do |_, error|
    Failbot.report(error)
  end

  def perform(org, user)
    # packages v2 is not available in GHES (yet), so simply consume these events
    # so that they do not stay enqueued
    return if GitHub.enterprise?

    offset = 0

    loop do
      packages = PackageRegistry::Twirp.metadata_client.get_all_packages(
        namespace: org.login,
        limit: BATCH_SIZE,
        offset: offset,
      )

      break if packages.empty?

      packages.each do |package|
        # Revoke all roles for this user
        with_write do
          Role.system_package_roles.each do |role|
            Permissions::Granters::RoleGranter.new(actor: user, target: package, role: role).revoke_if_exists!
          end
        end

        GitHub.dogstats.increment("org.packages.user_removed")
      end

      # we're done if this was the last or only batch
      break if packages.count < BATCH_SIZE

      offset += packages.count - 1
    end
  end
end
