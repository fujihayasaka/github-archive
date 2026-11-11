# typed: true
# frozen_string_literal: true

class WidenUploadManifestFilesBlobOidForSha256 < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::AssetObjects)

  def change
    reversible do |dir|
      change_table :upload_manifest_files, bulk: true do |t|
        dir.up do
          t.change :blob_oid, "varchar(64)", default: nil
        end

        dir.down do
          t.change :blob_oid, "varchar(40)", default: nil
        end
      end
    end
  end
end
