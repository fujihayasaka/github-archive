# typed: true
# frozen_string_literal: true

class DropFlipperGates < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    drop_table :flipper_gates, if_exists: true
  end
end
