# typed: true

class RemovePagesSourceRefSubdomainRepositoryIdIndexes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :pages, bulk: true do |t|
      t.remove_index name: :index_pages_on_source_ref_name, column: :source_ref_name, length: 30
      t.remove_index name: :index_subdomain_on_repository_id, column: [:subdomain, :repository_id]
    end
  end
end
