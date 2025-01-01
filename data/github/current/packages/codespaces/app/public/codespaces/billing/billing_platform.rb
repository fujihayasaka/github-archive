# typed: strict
# frozen_string_literal: true

# This file is intended as a place to store anything pertaining to Billing vNext that is used
# in multiple places in the Codespaces Dotcom AoR. For example, in both the handlers and in the controllers.
module Codespaces
  module Billing
    module BillingPlatform
      # These constants aren't in Codespaces::Skus because Skus represents our machine type offerings
      # shared with the Codespaces service. These Skus represent what we bill for in Billing vNext,
      # which doesn't always line up with a machine type.
      STORAGE_SKU = "codespaces_storage"
      PREBUILD_STORAGE_SKU = "codespaces_prebuild_storage"
      COMPUTE_D2_SKU = "codespaces_compute_d2"
      COMPUTE_D4_SKU = "codespaces_compute_d4"
      COMPUTE_D8_SKU = "codespaces_compute_d8"
      COMPUTE_D16_SKU = "codespaces_compute_d16"
      COMPUTE_D32_SKU = "codespaces_compute_d32"

      COMPUTE_SKUS = T.let([COMPUTE_D2_SKU, COMPUTE_D4_SKU, COMPUTE_D8_SKU, COMPUTE_D16_SKU, COMPUTE_D32_SKU].freeze, T::Array[String])
    end
  end
end
