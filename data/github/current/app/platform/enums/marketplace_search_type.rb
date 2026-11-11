# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MarketplaceSearchType < Platform::Enums::Base
      description "Represents available types of result you can get back from a Marketplace search."
      visibility :internal

      value "MARKETPLACE", "GitHub Marketplace listings", value: "marketplace"
      value "MARKETPLACE_TOOLS", "GitHub Marketplace listings and actions", value: "marketplace-tools"
      value "MARKETPLACE_ACTIONS", "GitHub Marketplace actions", value: "repository-action"
      value "MARKETPLACE_STACKS", "GitHub Marketplace stacks", value: "repository-stack"
    end
  end
end
