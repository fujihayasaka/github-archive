# typed: true
# frozen_string_literal: true

require "github/transitions/20220713184159_backfill_memex_mobile_oauth_scopes"

class BackfillMemexMobileOauthScopesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    transition = GitHub::Transitions::BackfillMemexMobileOauthScopes.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
