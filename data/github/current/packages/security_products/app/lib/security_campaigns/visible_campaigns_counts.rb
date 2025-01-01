# typed: strict
# frozen_string_literal: true

module SecurityCampaigns
  class VisibleCampaignsCounts < T::Struct
    const :open_campaigns_count, Integer
    const :open_campaigns_total_count, Integer
    const :open_campaigns_open_count, Integer
    const :open_campaigns_in_progress_count, Integer
    const :open_campaigns_fixed_count, Integer
    const :open_campaigns_dismissed_count, Integer
    const :closed_campaigns_count, Integer
    const :closed_campaigns_total_count, Integer
    const :closed_campaigns_open_count, Integer
    const :closed_campaigns_fixed_count, Integer
    const :closed_campaigns_dismissed_count, Integer
    const :draft_campaigns_count, Integer
    const :autofix_generated_count, Integer
    const :autofix_applied_count, Integer
  end
end
