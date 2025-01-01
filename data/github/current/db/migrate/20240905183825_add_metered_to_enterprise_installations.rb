# typed: true
# frozen_string_literal: true

class AddMeteredToEnterpriseInstallations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)
  def change
    add_column :enterprise_installations, :metered, :boolean, default: false, null: false
  end
end
