# typed: strict
# frozen_string_literal: true

module GitHubSponsors
  # Define Sponsors-wide Sorbet type aliases
  module Types
    Sponsor = T.type_alias { T.any(User, Organization) }

    class SponsorOrder < T::Enum
      enums do
        Relevance = new
        Login = new
      end
    end

    Sponsorable = T.type_alias { T.any(User, Organization) }

    class SponsorableOrder < T::Enum
      enums do
        Relevance = new
        Login = new
      end
    end

    class SponsorAndLifetimeValueOrder < T::Enum
      enums do
        SponsorRelevance = new("sponsor_relevance")
        SponsorLogin = new("sponsor_login")
        LifetimeValue = new("lifetime_value")
      end
    end
  end
end
