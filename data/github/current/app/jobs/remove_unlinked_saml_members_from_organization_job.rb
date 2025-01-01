# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class RemoveUnlinkedSamlMembersFromOrganizationJob < ApplicationJob
  queue_as :remove_unlinked_saml_members_from_organization

  def perform(organization_id, actor_id)
    return unless organization = Organization.find_by_id(organization_id)
    return unless actor = User.find_by_id(actor_id)
    return unless organization.adminable_by?(actor)

    log_info("Starting remove_unlinked_saml_members_from_organization job", organization_id, organization.name, actor_id)

    organization.unlinked_saml_members.find_each do |member|
      begin
        if organization.adminable_by?(member)
          # Run removal of admins synchronously as the RemoveOrgAdminJob uses a lock to ensure only
          # a single instance runs at a time. When too many admin removals are enqueued these jobs
          # can time out and leave the admins in the organization. Running them inline here sidesteps
          # the use of these locks entirely.
          with_write { organization.remove_member!(member, reason: Organization::RemovedMemberNotification::SAML_EXTERNAL_IDENTITY_MISSING) }
        else
          with_write { organization.remove_member(member, reason: Organization::RemovedMemberNotification::SAML_EXTERNAL_IDENTITY_MISSING) }
        end
        with_write do
          Organization::RemovedMemberNotification.new(organization, member).add_saml_external_identity_missing
        end
      rescue => error
        # We still want to surface any exceptions to Failbot, but not interrupt the execution.
        Failbot.report(error, {
          "user_id" => member.id,
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.organization.id" => organization_id,
          "gh.organization.name" => organization.name,
          "gh.actor.id" => actor_id,
          "gh.caller" => caller.to_s
        })
      end
    end

    log_info("Finished remove_unlinked_saml_members_from_organization job", organization_id, organization.name, actor_id)
  end

  private

  def log_info(message, organization_id, organization_name, actor_id)
    GitHub.logger.info(
      "info.message" => message,
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.organization.id" => organization_id,
      "gh.organization.name" => organization_name,
      "gh.actor.id" => actor_id,
      "gh.caller" => caller.to_s
    )
  end
end
