# typed: true
class AddPlanCodespacesPrebuildTemplates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_reference :codespace_prebuild_templates, :plan, unsigned: true, index: false, null: true
  end
end
