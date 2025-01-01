# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorshipPaymentSource < Platform::Enums::Base
      description "How payment was made for funding a GitHub Sponsors sponsorship."

      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      value "GITHUB", "Payment was made through GitHub.", value: "github"
      value "PATREON", "Payment was made through Patreon.", value: "patreon"
    end
  end
end
