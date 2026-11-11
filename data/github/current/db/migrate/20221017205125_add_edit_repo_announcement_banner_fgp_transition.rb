# typed: true
# frozen_string_literal: true

require "github/transitions/20221017205125_add_edit_repo_announcement_banner_fgp"

class AddEditRepoAnnouncementBannerFgpTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddEditRepoAnnouncementBannerFgp.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
