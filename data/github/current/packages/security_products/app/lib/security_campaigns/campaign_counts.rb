# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class CampaignCounts
    sig { returns(Integer) }
    attr_reader :open_count

    sig { returns(Integer) }
    attr_reader :closed_count

    sig { returns(Integer) }
    attr_reader :open_with_links_count

    sig { returns(Integer) }
    attr_reader :open_without_links_count

    sig { returns(Integer) }
    attr_reader :total_count

    sig do params(
      open_count: Integer,
      closed_count: Integer,
      open_with_links_count: Integer,
    ).void
    end
    def initialize(
      open_count:,
      closed_count:,
      open_with_links_count:
    )
      @open_count = open_count
      @closed_count = closed_count
      @open_with_links_count = open_with_links_count

      @total_count = T.let(@open_count + @closed_count, Integer)
      @open_without_links_count = T.let(@open_count - @open_with_links_count, Integer)
    end

    sig { returns(CampaignCounts) }
    def self.empty
      new(
        open_count: 0,
        closed_count: 0,
        open_with_links_count: 0
      )
    end
  end
end
