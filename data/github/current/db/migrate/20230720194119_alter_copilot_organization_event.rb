# typed: true
class AlterCopilotOrganizationEvent < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_organization_events, bulk: true do |t|
      t.remove_index name: "index_copilot_organization_events_on_organization_id"
      t.remove_index name: "index_copilot_organization_events_on_user_id"
      t.index [:organization_id, :event_type], name: "index_copilot_organization_events_on_org_id_event_type"
      t.index [:user_id, :event_type], name: "index_copilot_organization_events_on_user_id_event_type"
    end
  end
end
