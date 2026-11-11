# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveOutsideCollaboratorFromOrganizationJob < ApplicationJob
  queue_as :remove_outside_collaborator_from_organization

  retry_on_dirty_exit

  resolve_tenant_context do |_user_id, organization_id|
    org = Organization.find_by(id: organization_id)
    org&.business
  end

  def perform(user_id, organization_id, options = {})
    reason = options["reason"] || options[:reason]
    save_settings = options["save_settings"] || options[:save_settings]
    send_notification = options["send_notification"] || options[:send_notification]

    return unless user = User.find_by(id: user_id)
    return unless org = Organization.find_by(id: organization_id)

    with_write { org.remove_outside_collaborator!(user, save_settings: save_settings, reason: reason, send_notification: send_notification) }
  end
end
