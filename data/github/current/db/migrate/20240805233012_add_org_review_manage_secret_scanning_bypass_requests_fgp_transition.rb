# typed: true
# frozen_string_literal: true

require "github/transitions/20240805233012_add_org_review_manage_secret_scanning_bypass_requests_fgp"

class AddOrgReviewManageSecretScanningBypassRequestsFgpTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Iam)
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddOrgReviewManageSecretScanningBypassRequestsFgp.new(arguments)
    transition.run
  end

  def self.down
  end
end
