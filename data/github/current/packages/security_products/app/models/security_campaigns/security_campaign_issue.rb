# typed: strict
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaignIssue < ApplicationRecord::Domain::SecurityCampaigns
  belongs_to :security_campaign
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :issue

  sig { returns(T.nilable(Issue)) }
  def issue_following_transfers
    return issue unless issue.nil? # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    new_id = IssueTransfer.find_new_id_by_original_id(original_id: issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return nil if new_id.nil?

    Issue.find_by(id: new_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end
end
