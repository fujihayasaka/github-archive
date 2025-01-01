# frozen_string_literal: true

class AddCWETable < ActiveRecord::Migration[6.0]
  def change
    create_table :cwes, id: false do |t|
      # CWEs will all take form of CWE-####.
      # The highest is currently CWE-1304, which is 8 characters.
      # limit is 9 to leave room for future 9 character CWE
      t.string :cwe_id, limit: 9, null: false, primary_key: true

      # the longest cwe "name" is 508 characters.  Limit of 1000 to leave room for the future.
      t.string :name, limit: 1000, null: false
    end
  end
end
