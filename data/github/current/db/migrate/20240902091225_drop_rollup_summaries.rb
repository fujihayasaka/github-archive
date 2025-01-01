# typed: true
# frozen_string_literal: true

class DropRollupSummaries < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Mysql2)

  def change
    drop_table :rollup_summaries, if_exists: true
  end
end
