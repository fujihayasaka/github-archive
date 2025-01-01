# typed: true
# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module GitHub
  module Aqueduct
    autoload :Client, "github/aqueduct/client"
    autoload :Job, "github/aqueduct/job"
    autoload :HydroMessageJobContext, "github/aqueduct/hydro_message_job_context"
    autoload :ActiveJobContext, "github/aqueduct/active_job_context"
    autoload :CompositeBackend, "github/aqueduct/composite_backend"

    COMPONENT = :aqueduct
    LARGE_PAYLOAD_SIZE_MIN = 5242880  # 5MiB
    LARGE_PAYLOAD_SIZE_MAX = 26214400 # 25MiB
    # Delivery times cannot exceed the aqueduct limit of 7 days. We limit to
    # less than that to ensure we're not on the validation boundary.
    MAX_DELIVERY_TIMESTAMP_FUTURE_DURATION = 5.days

    # Public: Checks if the payload size is considered "large" to aqueduct.
    #
    # size_bytes - The payload size in bytes.
    #
    # Returns a boolean for whether the size is large.
    def self.is_payload_size_large?(size_bytes)
      size_bytes.between?(LARGE_PAYLOAD_SIZE_MIN, LARGE_PAYLOAD_SIZE_MAX)
    end
  end
end
