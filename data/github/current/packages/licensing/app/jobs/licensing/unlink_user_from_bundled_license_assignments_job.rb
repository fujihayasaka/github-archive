# typed: strict
# frozen_string_literal: true

class Licensing::UnlinkUserFromBundledLicenseAssignmentsJob < ApplicationJob
  queue_as :licensing
  retry_on_dirty_exit

  before_enqueue do |_job|
    throw(:abort) if GitHub.single_business_environment?
  end

  sig { params(user_id: Integer).void }
  def perform(user_id)
    with_write do
      Licensing::BundledLicenseAssignment.where(user_id: user_id).each do |bla|
        # ensure update-related callbacks on the model are triggered
        # (ie. creates audit logs)
        bla.update!(user_id: nil)
      end
    end
  end
end
