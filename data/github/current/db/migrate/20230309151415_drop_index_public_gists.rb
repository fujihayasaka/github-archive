# typed: true
# frozen_string_literal: true

class DropIndexPublicGists < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Gists)

  def change
    drop_table :index_public_gists, if_exists: true
  end
end
