# typed: true

class ChangeIntegrationsVisibilityDefaultValueToPrivate < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_column_default :integrations, :visibility, from: 0, to: 1
  end
end
