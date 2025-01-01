# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class DetailedCampaignCounts < CampaignCounts
    sig { returns(Integer) }
    attr_reader :dismissed_count

    sig { returns(Integer) }
    attr_reader :autofix_supported_count

    sig { returns(Integer) }
    attr_reader :autofix_generated_count

    sig { returns(Integer) }
    attr_reader :autofix_accepted_count

    sig do params(
      open_count: Integer,
      closed_count: Integer,
      open_with_links_count: Integer,
      dismissed_count: Integer,
      autofix_supported_count: Integer,
      autofix_generated_count: Integer,
      autofix_accepted_count: Integer
    ).void
    end
    def initialize(
      open_count:,
      closed_count:,
      open_with_links_count:,
      dismissed_count:,
      autofix_supported_count:,
      autofix_generated_count:,
      autofix_accepted_count:
    )
      super(open_count:, closed_count:, open_with_links_count:)
      @dismissed_count = dismissed_count
      @autofix_supported_count = autofix_supported_count
      @autofix_generated_count = autofix_generated_count
      @autofix_accepted_count = autofix_accepted_count
    end

    sig { returns(DetailedCampaignCounts) }
    def self.empty
      new(
        open_count: 0,
        closed_count: 0,
        open_with_links_count: 0,
        dismissed_count: 0,
        autofix_supported_count: 0,
        autofix_generated_count: 0,
        autofix_accepted_count: 0
      )
    end
  end
end
