# typed: true
# frozen_string_literal: true

class AllowNullDescriptionOnSecurityConfiguration < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)
  def change
    change_column_null :security_configurations, :description, true
  end
end
