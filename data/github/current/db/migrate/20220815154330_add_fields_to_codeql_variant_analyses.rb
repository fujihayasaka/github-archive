# typed: false
class AddFieldsToCodeqlVariantAnalyses < ActiveRecord::Migration[7.1]
  def self.up
    change_table :codeql_variant_analyses, bulk: true do |t|
      t.column :not_found_repo_nwos, :text, null: true
    end
  end

  def self.down
    change_table :codeql_variant_analyses, bulk: true do |t|
      t.remove :not_found_repo_nwos
    end
  end
end
