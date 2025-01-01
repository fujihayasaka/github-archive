# frozen_string_literal: true

class AddBlocklistedTermsType < ActiveRecord::Migration[7.0]
  def change
    add_column :blocklisted_terms, :term_type, :string, null: false, default: "content"
  end
end
