# frozen_string_literal: true

class AddIndexOnBlacklistedTermsPattern < ActiveRecord::Migration[5.2]
  def change
    add_index :blacklisted_terms, :pattern
  end
end
