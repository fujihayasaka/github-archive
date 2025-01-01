# typed: strict
# frozen_string_literal: true

class Licensing::UnlinkUserFromBundledLicenseAssignmentsJob < ApplicationJob
  queue_as :licensing
  retry_on_dirty_exit

  before_enqueue do |_job|
    throw(:abort) if GitHub.single_business_environment?
  end

  sig { params(user_id: Integer, business_id: T.nilable(Integer), reason: T.nilable(Symbol)).void }
  def perform(user_id, business_id = nil, reason: nil)
    unlink_blas = Licensing::BundledLicenseAssignment.where(user_id: user_id)
    unlink_blas = unlink_blas.where(business_id: business_id) if business_id.present?
    with_write do
      unlink_blas.each do |bla|
        bla.unassign!(reason: reason)
      end
    end
  end
end
