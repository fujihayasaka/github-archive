class ChangeDocumentTypeInCopilotIgnores < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def up
    change_column :copilot_ignores, :document, :mediumblob
  end

  def down
    change_column :copilot_ignores, :document, :blob
  end
end
