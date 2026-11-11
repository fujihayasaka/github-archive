# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorAndLifetimeValueOrderField < Platform::Enums::Base
      description "Properties by which sponsor and lifetime value connections can be ordered."
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "SPONSOR_LOGIN", "Order results by the sponsor's login (username).",
        value: GitHubSponsors::Types::SponsorAndLifetimeValueOrder::SponsorLogin.serialize
      value "SPONSOR_RELEVANCE", "Order results by the sponsor's relevance to the viewer.",
        value: GitHubSponsors::Types::SponsorAndLifetimeValueOrder::SponsorRelevance.serialize
      value "LIFETIME_VALUE", "Order results by how much money the sponsor has paid in total.",
        value: GitHubSponsors::Types::SponsorAndLifetimeValueOrder::LifetimeValue.serialize
    end
  end
end
