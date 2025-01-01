# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateTeamSyncTenantJob < ApplicationJob
  queue_as :critical

  class ServiceUnavailable < RuntimeError; end

  retry_on(ServiceUnavailable, wait: 60.seconds, attempts: 3) do |_job, error|
    Failbot.report(error)
  end

  def perform(tenant)
    return unless tenant

    error = tenant.register

    if error
      raise ServiceUnavailable, error.inspect
    end
  end
end
