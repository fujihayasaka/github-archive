# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ConvertToOutsideCollaboratorJob < ApplicationJob
  queue_as :convert_to_outside_collaborator

  locked_by timeout: 10.minutes, key: ->(job) {
    [job.arguments[0], job.arguments[1]]
  }

  resolve_tenant_context do |org_id|
    org = Organization.find_by(id: org_id)
    org&.business
  end

  def perform(org_id, user_id, options = {})
    return unless org = Organization.find_by(id: org_id)
    return unless user = User.find_by(id: user_id)

    save_settings = options["save_settings"] || options[:save_settings]

    with_write do
      begin
        org.convert_to_outside_collaborator!(user, save_settings: save_settings)
      rescue Organization::CannotConvertNonMemberToCollaboratorError
        # Skip attempting to convert the user if they are not a member
      end
    end
    org.business&.update_license_usage
  end
end
