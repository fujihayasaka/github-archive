# typed: true
class AddUniquenessOnRepositoryRulesetsName < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rulesets, bulk: true do |t|
      t.index [:source_id, :source_type, :name], unique: true, name: "index_repository_rulesets_on_source_id_and_source_type_and_name"
      t.remove_index name: "index_repository_rulesets_source"
    end
  end
end
