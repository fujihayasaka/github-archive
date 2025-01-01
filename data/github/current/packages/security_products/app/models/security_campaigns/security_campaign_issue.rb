# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignIssue < ApplicationRecord::Domain::SecurityCampaigns
  belongs_to :security_campaign
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  belongs_to :issue

  sig { returns(T.nilable(Issue)) }
  def issue_following_transfers
    return issue unless issue.nil?

    new_id = IssueTransfer.find_new_id_by_original_id(original_id: issue_id)
    return nil if new_id.nil?

    Issue.find_by(id: new_id)
  end
end
