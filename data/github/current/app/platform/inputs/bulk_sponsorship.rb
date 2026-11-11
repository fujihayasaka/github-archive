# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class BulkSponsorship < Platform::Inputs::Base
      description "Information about a sponsorship to make for a user or organization with a GitHub Sponsors " \
        "profile, as part of sponsoring many users or organizations at once."

      argument :sponsorable_id, ID, "The ID of the user or organization who is receiving the sponsorship. Required " \
        "if sponsorableLogin is not given.", required: false, loads: Interfaces::Sponsorable
      argument :sponsorable_login, String, "The username of the user or organization who is receiving the " \
        "sponsorship. Required if sponsorableId is not given.", required: false
      argument :amount, Integer, "The amount to pay to the sponsorable in US dollars. " \
        "Valid values: 1-#{::SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS}.", required: true
    end
  end
end
