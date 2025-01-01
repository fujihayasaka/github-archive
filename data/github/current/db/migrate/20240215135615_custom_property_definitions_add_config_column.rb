class CustomPropertyDefinitionsAddConfigColumn < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :custom_property_definitions, :config, :json
  end
end
