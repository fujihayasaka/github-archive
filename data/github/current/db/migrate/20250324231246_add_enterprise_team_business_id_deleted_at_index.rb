# typed: strict
# frozen_string_literal: true

class AddEnterpriseTeamBusinessIdDeletedAtIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def change
    add_index :enterprise_teams, [:business_id, :deleted_at]
  end
end
