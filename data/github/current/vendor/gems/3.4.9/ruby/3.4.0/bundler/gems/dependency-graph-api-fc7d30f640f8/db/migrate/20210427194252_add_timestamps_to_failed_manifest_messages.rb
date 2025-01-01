class AddTimestampsToFailedManifestMessages < ActiveRecord::Migration[6.0]
  def change
    add_timestamps(:dg_failed_manifest_messages, null: true)
  end
end
