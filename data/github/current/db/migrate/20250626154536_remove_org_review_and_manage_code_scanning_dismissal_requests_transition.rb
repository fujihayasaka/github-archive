# typed: true
# frozen_string_literal: true

require "github/transitions/20250626154536_remove_org_review_and_manage_code_scanning_dismissal_requests"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class RemoveOrgReviewAndManageCodeScanningDismissalRequestsTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::RemoveOrgReviewAndManageCodeScanningDismissalRequests.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
