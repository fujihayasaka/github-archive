class DropPrimaryLanguageNameIdAndPublicIndexOnRepositories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :repositories, bulk: true do |t|
      t.remove_index name: "index_repositories_on_primary_language_name_id_and_public", column: [:primary_language_name_id, :public]
    end
  end
end
