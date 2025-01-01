# typed: true

class GuidPerformanceModelsAttachments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def up
    change_table :models_attachments, bulk: true do |t|
      t.change :guid, "BINARY(16)"

      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn there is only a handful of testing records
      t.index [:guid, :uploader_id], unique: true
    end
  end

  def down
    change_table :models_attachments, bulk: true do |t|
      t.change :guid, :string, limit: 36
      t.remove_index [:guid, :uploader_id]
    end
  end
end
