# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
class WidenUploadManifestsCommitOidForSha256 < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    reversible do |dir|
      change_table :upload_manifests, bulk: true do |t|
        dir.up do
          t.change :commit_oid, "varchar(64)", default: nil
        end

        dir.down do
          t.change :commit_oid, "varchar(40)", default: nil
        end
      end
    end
  end
end
# rubocop:enable GitHub/ExistingIdColumnsMustBeBigint
