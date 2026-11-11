# typed: true

class AddOrgVisibilityToSparkRuntimeApp < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table(:runtime_apps, bulk: true) do |t|
      t.column :visibility_organization_id, :bigint, unsigned: true, null: true, comment: "The organization that this RuntimeApp is visible to, if selected."
    end
  end
end
