# typed: true

class SecretScanningTokenScanResultsScanId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up

    ## Changes the default charset and collation for the table, but if you run this it will override any column definitions
    ## thefore we have to run this first, to then alter our charset and collation for token_type and signature to ascii
    ## after this runs.
    connection.execute(<<~SQL)
    ALTER TABLE token_scan_results
    CONVERT TO
      CHARACTER SET utf8mb4
      COLLATE utf8mb4_unicode_520_ci
    SQL

    change_table(:token_scan_results, bulk: true) do |t|
      # Remove unused indices
      t.remove_index name: "index_token_scan_results_on_repo_resolution_created_updated_at"
      t.remove_index name: "index_token_scan_results_on_repo_token_type_resolved"
      t.remove_index name: "index_token_scan_results_on_repo_token_type_resolution_created"
      t.remove_index name: "index_token_scan_results_on_repo_token_type_resolution_updated"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_token_type_created"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_token_type_updated"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_created"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_updated"

      # Recreate this index with the same name, but include updated_at as a covering index for sort operations
      t.remove_index name: "index_token_scan_results_on_repo_resolved_type_created"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_type_updated"
      t.index [:repository_id, :has_valid_locations, :resolved, :token_type, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolved_type_created", comment: "covering index for both valid locations type and resolved"

      # Add missing column comments; indicate which fields are immutable, and which must be included the audit table
      t.change :created_at, "datetime(3)", null: false
      t.change :updated_at, "datetime(3)", null: false
      t.change :repository_id, "bigint(20)", unsigned: true, null: false, comment: "the repository_id that the secret was discovered in; immutable"
      t.change :token_type, "varchar(64) CHARACTER SET ascii", null: false, comment: "the internal-only token type; for a custom pattern this will start with cp_<pattern_id>; immutable", collation: "ascii_general_ci"
      t.change :token_signature, "varchar(64) CHARACTER SET ascii", null: false, comment: "the hex encoded sha256 checksum of the discovered secret; immutable", collation: "ascii_general_ci"
      t.change :resolution, "int(11)", null: true, default: nil, comment: "audited; internal enum/iota within the token-scanning-service representing the resolution (e.g., revoked, false positive)"
      t.change :resolver_id, "bigint(20)", unsigned: true, null: true, default: nil,  comment: "audited; if resolution is not null, this represents the github login ID that applied <resolutions>"
      t.change :resolved_at, "datetime(3)", null: true, default: nil, comment: "audited; if resolution is not null, the timestamp <resolution> was applied by <resolver_id>"
      t.change :number, "int(11)", unsigned: true, null: false, default: 0,  comment: "the repository-scoped sequence alert number; see token_scan_result_sequences; immutable"
      t.change :scan_scope, "tinyint(4)", unsigned: true, null: false, default: 0, comment: "internal enum/iota in the token-scanning-service representing the location where the scan was looking (e.g., repository content, commit content); immutable"
      t.change :resolved, "tinyint(1)", null: false, default: 0,  comment: "audited; boolean field based on the <resolution> field above; some non-null resolutions are considered false here (e.g., re-opened)"
      t.change :first_location_id, "bigint(20)", unsigned: true, null: true, default: nil,  comment: "audited; the token_scan_result_locations_v2.id of the first discovered location of this secret.  This value changes depending on the secret-scanning configurations ignored paths"
      t.change :has_valid_locations, "tinyint(1)", null: false, default: 0, comment: "audited; boolean; this is a performnce-only column useful as an index, which is based on whether first_location_id > 0"
      t.change :custom_pattern_id, "bigint(20)", unsigned: true, null: true, default: nil, comment: "the secret_scan_custom_patterns.id that this token_type belongs to; allows faster joins than using a parsed cp_<id> token_type; immutable"

      # Add a new columns, with a supporting index
      t.column :scan_id, "bigint(20)", null: true, unsigned: true, comment: "the secret_scanning_scans.id which this record was found in, if any; immutable"
      t.index [:scan_id], name: "index_token_scan_results_scan_id", comment: "for looking up records by an explicit scan which created it"
      t.column :bypass_id, "bigint(20)", null: true, unsigned: true, comment: "if not null, the secret_scanning_push_protections_bypass.id that allowed a push to succeed; immutable"
      t.column :resolution_comment, "VARCHAR(280) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci", null: true, comment: "audited; user-provided comment explaining the resolution status, if any"
    end

    change_table_comment(:token_scan_results, "table that holds alerts for discovered secrets for repositories; all mutable columns should be marked as audited, and included in inside audit_token_scan_results")

  end

  def down
    change_table(:token_scan_results, bulk: true) do |t|

      t.index [:repository_id, :resolution, :created_at, :updated_at], name: "index_token_scan_results_on_repo_resolution_created_updated_at"
      t.index [:repository_id, :token_type, :resolved], name: "index_token_scan_results_on_repo_token_type_resolved"
      t.index [:repository_id, :has_valid_locations, :token_type, :resolution, :created_at], name: "index_token_scan_results_on_repo_token_type_resolution_created"
      t.index [:repository_id, :has_valid_locations, :token_type, :resolution, :updated_at], name: "index_token_scan_results_on_repo_token_type_resolution_updated"
      t.index [:repository_id, :has_valid_locations, :resolved, :token_type, :created_at], name: "index_token_scan_results_on_repo_resolved_token_type_created"
      t.index [:repository_id, :has_valid_locations, :resolved, :token_type, :updated_at], name: "index_token_scan_results_on_repo_resolved_token_type_updated"
      t.index [:repository_id, :has_valid_locations, :resolved, :created_at], name: "index_token_scan_results_on_repo_resolved_created"
      t.index [:repository_id, :has_valid_locations, :resolved, :updated_at], name: "index_token_scan_results_on_repo_resolved_updated"

      t.index [:repository_id, :has_valid_locations, :token_type, :created_at], name: "index_token_scan_results_on_repo_resolved_type_created"
      t.index [:repository_id, :has_valid_locations, :token_type, :updated_at], name: "index_token_scan_results_on_repo_resolved_type_updated"
      t.remove_index name: "index_token_scan_results_on_repo_resolved_type_created"

      t.change :repository_id, "bigint(20)", unsigned: true, null: false, comment: nil
      t.change :created_at, "datetime", null: false
      t.change :updated_at, "datetime", null: false
      t.change :token_type, "varchar(64)", null: false, comment: nil
      t.change :token_signature, "varchar(64)", null: false, comment: nil
      t.change :resolution, "int(11)", null: true, comment: nil
      t.change :resolver_id, "bigint(20)", unsigned: true, null: true, comment: nil
      t.change :resolved_at, "datetime", null: true, comment: nil
      t.change :number, "int(11)", null: false, default: 0, comment: nil
      t.change :scan_scope, "tinyint(4)", null: false, default: 0, comment: nil
      t.change :resolved, "tinyint(1)", null: false, default: 0, comment: nil
      t.change :first_location_id, "bigint(20)", unsigned: true, null: true, default: nil, comment: nil
      t.change :has_valid_locations, "tinyint(1)", null: false, default: 0, comment: nil
      t.change :custom_pattern_id, "bigint(20)", unsigned: true, null: true, default: nil, comment: "the identifier to the custom pattern that generated this alert if applicable"

      t.remove :scan_id
      t.remove_index name: "index_token_scan_results_scan_id"
      t.remove :bypass_id
      t.remove :resolution_comment
    end

    change_table_comment(:token_scan_results, nil)

    connection.execute(<<~SQL)
      ALTER TABLE token_scan_results
      CONVERT TO
        CHARACTER SET utf8
        COLLATE utf8_general_ci
      SQL
  end
end
