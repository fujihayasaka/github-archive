# typed: true
# frozen_string_literal: true

class DropFlipperFeatures < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Mysql1)

  def change
    drop_table :flipper_features, if_exists: true
  end
end
