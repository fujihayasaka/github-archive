# typed: true
# frozen_string_literal: true

module UserHovercard::Contexts
  # Public: Used to provide context about a user who is sponsoring the viewer on GitHub Sponsors.
  class YourSponsor < Hovercard::Contexts::Base
    # private_sponsor - Boolean indicating whether this user has a private sponsorship for the
    #                   viewer
    # related_org_sponsors - Array of Organizations that are sponsoring the viewer; the user
    #                        shown in the hovercard should belong to these orgs
    def initialize(private_sponsor:, related_org_sponsors:)
      @private_sponsor = private_sponsor
      @related_org_sponsors = related_org_sponsors || []
    end

    def visible_related_org_sponsors
      @visible_related_org_sponsors ||= @related_org_sponsors.first(Hovercard::LIST_LENGTH)
    end

    def remaining_related_org_sponsor_count
      @remaining_related_org_sponsor_count ||= @related_org_sponsors.size -
        visible_related_org_sponsors.size
    end

    def message
      if private_sponsor?
        "Your private sponsor"
      else
        "Your sponsor"
      end
    end

    def octicon
      "heart-fill"
    end

    def private_sponsor?
      @private_sponsor
    end

    def corporate_sponsor?
      visible_related_org_sponsors.any?
    end

    def platform_type_name
      "GenericHovercardContext"
    end

    def test_selector
      adjectives = []
      adjectives << "private" if private_sponsor?
      adjectives << "corporate" if corporate_sponsor?
      parts = ["your"] + adjectives + ["sponsor"]
      parts.join("-")
    end
  end
end
