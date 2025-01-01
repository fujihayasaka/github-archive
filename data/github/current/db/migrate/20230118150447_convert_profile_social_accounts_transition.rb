# typed: true
# frozen_string_literal: true

require "github/transitions/20230118150447_convert_profile_social_accounts"

class ConvertProfileSocialAccountsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::ConvertProfileSocialAccounts.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
