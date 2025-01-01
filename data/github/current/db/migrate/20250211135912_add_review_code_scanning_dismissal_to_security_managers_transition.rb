# typed: true
# frozen_string_literal: true

require "github/transitions/20250211135912_add_review_code_scanning_dismissal_to_security_managers"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class AddReviewCodeScanningDismissalToSecurityManagersTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddReviewCodeScanningDismissalToSecurityManagers.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
