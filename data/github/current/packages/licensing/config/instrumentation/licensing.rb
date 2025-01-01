# typed: true
# frozen_string_literal: true

GlobalInstrumenter.subscribe("user.destroy") do |_name, _start, _ending, _transaction_id, payload|
  user = payload[:user]
  next unless user&.id

  Licensing::UnlinkUserFromBundledLicenseAssignmentsJob.perform_later(user.id)
end
