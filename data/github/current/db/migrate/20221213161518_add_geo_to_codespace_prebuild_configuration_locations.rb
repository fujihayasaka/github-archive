# typed: true

class AddGeoToCodespacePrebuildConfigurationLocations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    change_table(:codespace_prebuild_configuration_locations, bulk: true) do |t|
      t.column :geo, :tinyint
      t.index [:codespace_prebuild_configuration_id, :geo], name: "index_on_codespace_prebuild_configuration_id_and_geo"
    end
  end
end
