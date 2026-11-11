# frozen_string_literal: true

class AddGHSAIDToAdvisories < ActiveRecord::Migration[5.1]
  OLC_DIGITS = "23456789cfghjmpqrvwx"
  DIGIT_SQL = "SUBSTRING('#{OLC_DIGITS}', FLOOR(RAND() * #{OLC_DIGITS.length}) + 1, 1)".freeze
  GROUP_SQL = Array.new(4) { DIGIT_SQL }.join(", ")

  def up
    add_column :advisories, :ghsa_id, :string, limit: 19

    # Backfill GHSA IDs using a MySQL-ized version of our own GHSA ID
    # generation in Ruby, which as of this writing is:
    #
    #   SecureRandom.random_number(20 ** 12).
    #     to_s(20).
    #     rjust(17, "GHSA-000000000000").
    #     tr!("0123456789abcdefghij", "23456789cfghjmpqrvwx").
    #     insert(13, "-").
    #     insert(9, "-")
    execute <<~SQL.squish
      UPDATE
        advisories
      SET
        ghsa_id = CONCAT('GHSA-', #{GROUP_SQL}, '-', #{GROUP_SQL}, '-', #{GROUP_SQL})
      WHERE
        ghsa_id IS NULL
    SQL

    change_column_null :advisories, :ghsa_id, false
    add_index :advisories, :ghsa_id, unique: true
  end

  def down
    remove_index :advisories, :ghsa_id
    remove_column :advisories, :ghsa_id
  end
end
