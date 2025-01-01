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
    const :open_campaigns_count_with_spam, Integer
    const :draft_campaigns_count_with_spam, Integer
    const :has_open_spam, T::Boolean
    const :has_draft_spam, T::Boolean

    sig { returns(T::Hash[Symbol, Integer]) }
    def to_react_payload
      {
        openCampaignsCount: open_campaigns_count,
        openCampaignsTotalCount: open_campaigns_total_count,
        openCampaignsOpenCount: open_campaigns_open_count,
        openCampaignsInProgressCount: open_campaigns_in_progress_count,
        openCampaignsFixedCount: open_campaigns_fixed_count,
        openCampaignsDismissedCount: open_campaigns_dismissed_count,
        hasOpenSpam: has_open_spam,

        closedCampaignsCount: closed_campaigns_count,
        closedCampaignsTotalCount: closed_campaigns_total_count,
        closedCampaignsOpenCount: closed_campaigns_open_count,
        closedCampaignsFixedCount: closed_campaigns_fixed_count,
        closedCampaignsDismissedCount: closed_campaigns_dismissed_count,

        draftCampaignsCount: draft_campaigns_count,
        autofixGeneratedCount: autofix_generated_count,
        openCampaignsCountWithSpam: open_campaigns_count_with_spam,
        draftCampaignsCountWithSpam: draft_campaigns_count_with_spam,
        autofixAppliedCount: autofix_applied_count,
        hasDraftSpam: has_draft_spam
      }
    end
  end
end
