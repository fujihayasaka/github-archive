# typed: true
# frozen_string_literal: true

class AddIndexToTeamsOnBusinessIdTypeOrgSelectionType < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :teams, [:business_id, :type, :organization_selection_type], name: "index_teams_on_business_id_and_type_and_org_selection_type"
  end
end
