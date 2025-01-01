# typed: true
# frozen_string_literal: true

require "github/transitions/20240723162031_add_repo_review_manage_secret_scanning_bypass_requests_fgp"

class AddRepoReviewManageSecretScanningBypassRequestsFgpTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Iam)
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddRepoReviewManageSecretScanningBypassRequestsFgp.new(arguments)
    transition.run
  end

  def self.down
  end
end
