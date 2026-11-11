# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddChannelToOtpSmsTiming < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table :otp_sms_timings, bulk: true do |t|
      # Added at the behest of a linter asking to upgrade unrelated ID fields to BIGINT:
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id, :bigint, unsigned: true, null: false

      # the new column on the model
      t.column :channel, :string, limit: 16, null: true
    end
  end

  def down
    change_table :otp_sms_timings, bulk: true do |t|
      t.change :id, :integer, null: false, auto_increment: true
      t.change :user_id, :integer, unsigned: true, null: false
      t.remove :channel
    end
  end
end
