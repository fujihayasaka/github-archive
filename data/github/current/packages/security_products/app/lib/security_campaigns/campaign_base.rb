# typed: strict
# frozen_string_literal: true

module SecurityCampaigns

  # This class contains helper methods for accessing the functionality of a security campaign.
  class CampaignBase

    sig { params(security_campaign: SecurityCampaign, counts: CampaignCounts).void }
    def initialize(security_campaign, counts)
      @security_campaign = security_campaign
      @counts = counts
    end

    sig { returns(SecurityCampaign) }
    attr_reader :security_campaign

    sig { returns(Integer) }
    def open_count
      @counts.open_count
    end

    sig { returns(Integer) }
    def closed_count
      @counts.closed_count
    end

    sig { returns(Integer) }
    def total_count
      @counts.total_count
    end

    sig { returns(Integer) }
    def open_with_links_count
      @counts.open_with_links_count
    end

    sig { returns(Integer) }
    def open_without_links_count
      @counts.open_with_links_count
    end

    sig { returns(T.nilable(Integer)) }
    def id
      @security_campaign.id
    end

    sig { returns(Integer) }
    def number
      @security_campaign.number
    end

    sig { returns(String) }
    def name_for_display
      @security_campaign.name
    end

    sig { returns(Integer) }
    def days_left
      # We need to calculate the time similar to our React app to avoid discrepancy
      ((@security_campaign.ends_at - DateTime.current) / (60 * 60 * 24)).floor
    end

    sig { returns(Integer) }
    def closed_percentage
      return 0 if @counts.total_count == 0

      @counts.closed_count * 100 / @counts.total_count
    end

    sig do
      params(org: T.nilable(Organization)).
      returns(ActiveRecord::Relation)
    end
    private_class_method def self.targetable_repositories(org)
      return Repository.none if org.nil?

      org.repositories.active
    end
  end
end
