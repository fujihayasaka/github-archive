# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class HydroPublishViaAqueductJob < ApplicationJob
  queue_as :hydro_publish_via_aqueduct
  retry_on_dirty_exit

  class HydroPublishError < StandardError; end
  retry_on HydroPublishError, wait: :polynomially_longer, attempts: 8

  def perform(payload, schema:, partition_key: nil, **options)
    result = GitHub.sync_hydro_publisher.publish(payload, schema:, partition_key:, **options)
    unless result.success?
      raise HydroPublishError, "Failed to publish to Hydro: #{result.error_message}"
    end
  end
end
