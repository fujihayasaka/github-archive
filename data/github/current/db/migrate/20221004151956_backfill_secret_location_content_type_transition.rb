# typed: true
# frozen_string_literal: true

require "github/transitions/20221004151956_backfill_secret_location_content_type"

class BackfillSecretLocationContentTypeTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillSecretLocationContentType.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
