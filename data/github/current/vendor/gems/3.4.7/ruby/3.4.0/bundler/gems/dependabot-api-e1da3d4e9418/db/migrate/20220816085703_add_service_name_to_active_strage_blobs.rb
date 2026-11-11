# frozen_string_literal: true

require "dependabot/transitions/20220816085937_set_active_storage_blob_service_name"

# This migration comes from active_storage (originally 20190112182829), but
# split up into multiple migrations to work with gh-ost
# (https://github.com/github/gh-ost)
class AddServiceNameToActiveStrageBlobs < ActiveRecord::Migration[6.0]
  def up
    return if column_exists?(:active_storage_blobs, :service_name)

    add_column :active_storage_blobs, :service_name, :string

    return unless Dependabot.enterprise?

    transition = Dependabot::Transitions::SetActiveStorageBlobServiceName.new(dry_run: false)
    transition.perform
  end

  def down
    remove_column :active_storage_blobs, :service_name
  end
end
