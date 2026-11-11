# typed: true

class RemoveIndexLanguagesOnSize < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table(:languages, bulk: true) do |t|
      t.remove_index column: [:size], name: "index_languages_on_size"
    end
  end
end
