# typed: true

class RemoveNotFoundRepoIdsFromCodeqlVariantAnalyses < ActiveRecord::Migration[7.1]
  def up
    remove_column :codeql_variant_analyses, :not_found_repo_ids
  end

  def down
    add_column :codeql_variant_analyses, :not_found_repo_ids, :text, null: true
  end
end
