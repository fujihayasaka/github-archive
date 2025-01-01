# typed: true
# frozen_string_literal: true

class RemoveDownloads < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    drop_table :downloads, if_exists: true
  end
end
