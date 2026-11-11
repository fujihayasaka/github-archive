# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
#
# The DoNotAddUniqueIndexToExistingColumn rule can be disabled because this
# feature isn't even staffshipped and has just a handful of records, all of
# which should be unique until now.

class AddCodingGuidelineUniquenessConstraint < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_coding_guidelines, bulk: true do |t|
      t.index [:repository_id, :name], unique: true, name: "copilot_code_guidelines_repo_id_and_name"
      t.remove_index :repository_id
    end
  end
end
