# typed: true

class DropLanguageNameAndIdIndexOnLanguages < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :languages, bulk: true do |t|
      t.remove_index name: "index_languages_on_language_name_id"
    end
  end
end
