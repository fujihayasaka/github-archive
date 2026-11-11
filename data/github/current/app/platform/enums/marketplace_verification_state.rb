# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceVerificationState < Platform::Enums::Base
      description "The possible verifications state of a Marketplace listing."
      visibility :internal

      value "UNVERIFIED", "The listing has been approved as unverified for display in the GitHub Marketplace.", value: "unverified"
      value "VERIFIED", "The listing has been approved as verified for display in the GitHub Marketplace.", value: "verified"
      value "VERIFIED_CREATOR", "The listing has been approved as a verified creator", value: "verified_creator"
    end
  end
end
