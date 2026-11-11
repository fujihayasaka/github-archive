# typed: strict

class AddDocumentationColumnsToCopilotModelRegistryCache < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  sig { void }
  def change
    change_table :model_registry_cache, bulk: true do |t|
      t.string :documentation_link
      t.string :documentation_link_text
    end
  end
end
