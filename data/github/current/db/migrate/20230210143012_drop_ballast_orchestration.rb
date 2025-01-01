# typed: true
# frozen_string_literal: true

class DropBallastOrchestration < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Ballast)

  def change
    drop_table :ballast_orchestrations, if_exists: true
  end
end
