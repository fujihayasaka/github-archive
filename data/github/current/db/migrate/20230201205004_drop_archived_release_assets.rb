# typed: true
# frozen_string_literal: true

class DropArchivedReleaseAssets < ActiveRecord::Migration[7.1]
  def change
    drop_table :archived_release_assets, if_exists: true
  end
end
