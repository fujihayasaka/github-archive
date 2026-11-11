# typed: true
# frozen_string_literal: true

class AddIndexOnBusinessIdOnEnterpriseContributions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_index :enterprise_contributions, :business_id
  end
end
