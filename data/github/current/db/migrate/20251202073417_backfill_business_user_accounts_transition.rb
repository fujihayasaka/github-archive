# typed: true
# frozen_string_literal: true

require "github/transitions/20251202073417_backfill_business_user_accounts"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class BackfillBusinessUserAccountsTransition < ActiveRecord::Migration[8.1]
  def self.up
    # no-op, superceded by 20260130155934_backfill_business_user_accounts_transition_v2
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
