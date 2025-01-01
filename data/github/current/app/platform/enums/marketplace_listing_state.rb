# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceListingState < Platform::Enums::Base
      description "The possible states of a Marketplace listing."
      visibility :internal

      value "DRAFT", "The owner is preparing the listing.", value: "draft"
      value "UNVERIFIED_PENDING", "The owner has requested that the listing be approved as unverified.", value: "unverified_pending"
      value "VERIFICATION_PENDING_FROM_DRAFT", "The owner has requested that a draft listing be approved as verified.", value: "verification_pending_from_draft"
      value "VERIFICATION_PENDING_FROM_UNVERIFIED", "The owner has requested that an unverified listing be approved as verified.", value: "verification_pending_from_unverified"
      value "UNVERIFIED", "The listing has been approved as unverified for display in the GitHub Marketplace.", value: "unverified"
      value "VERIFIED", "The listing has been approved as verified for display in the GitHub Marketplace.", value: "verified"
      value "REJECTED", "The listing has been rejected for display in the GitHub Marketplace.", value: "rejected"
      value "ARCHIVED", "The listing has been removed from the GitHub Marketplace.", value: "archived"
      value "VERIFIED_CREATOR", "The listing has been approved as a verified creator", value: "verified_creator"
    end
  end
end
