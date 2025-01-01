# typed: true
class AddMaintenanceRetriesToGists < ActiveRecord::Migration[7.1]
  def change
    add_column :gists, :maintenance_retries, :integer, default: 0
  end
end
