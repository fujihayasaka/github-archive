# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Removes granular permissions for a removed org member from the orgs packages
class RemoveOrgMemberPackageAccessV2Job < ApplicationJob
  queue_as :remove_org_member_package_access_v2

  retry_on_dirty_exit

  retry_on(PackageRegistry::Twirp::BaseError, wait: 5.seconds, attempts: 10) do |_, error|
    Failbot.report(error)
  end

  def perform(user, packages)
    # packages v2 is not available in GHES (yet), so simply consume these events
    # so that they do not stay enqueued
    return if GitHub.enterprise?

    packages.each do |package|
      # Revoke all roles for this user
      with_write do
        Role.system_package_roles.each do |role|
          Permissions::Granters::RoleGranter.new(actor: user, target: package, role: role).revoke_if_exists!
        end
      end

      GitHub.dogstats.increment("org.packages.user_removed")
    end
  end
end
