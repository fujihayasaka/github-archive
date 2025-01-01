# typed: true
# frozen_string_literal: true

class IncreaseUserProgrammaticAccessDescriptionLimit < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Permissions)

  def up
    change_column :user_programmatic_accesses, :description, "varchar(1024)", default: nil
  end

  def down
    change_column :user_programmatic_accesses, :description, "varchar(120)", default: nil
  end
end
