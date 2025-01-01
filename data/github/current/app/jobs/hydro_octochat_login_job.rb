# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroOctochatLoginJob < HydroMessageJob
  queue_as :hydro_octochat_login
  retry_on_dirty_exit

  class_attribute :executions, instance_accessor: false
  self.executions = 0

  def perform
    Rails.logger.debug "octochat login: #{message.inspect}"
    self.class.executions += 1
  end
end
