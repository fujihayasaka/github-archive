# frozen_string_literal: true

class RenameBlacklistedTermsToBlocklistedTerms < ActiveRecord::Migration[5.2]
  def up
    rename_index :blacklisted_terms, "index_blacklisted_terms_on_pattern", "index_blocklisted_terms_on_pattern"
    rename_table :blacklisted_terms, :blocklisted_terms
  end

  def down
    rename_index :blocklisted_terms, "index_blocklisted_terms_on_pattern", "index_blacklisted_terms_on_pattern"
    rename_table :blocklisted_terms, :blacklisted_terms
  end
end
