# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MigratableResourceState < Platform::Enums::Base
      description "The state of a migratable resource."
      feature_flag :gh_migrator_import_to_dotcom

      # pending states
      value "EXPORT", "The migratable resource is configured to be exported.", value: "export"
      value "IMPORT", "The migratable resource is configured to be imported.", value: "import"
      value "MAP", "The migratable resource is configured to be mapped.", value: "map"
      value "RENAME", "The migratable resource is configured to be renamed.", value: "rename"
      value "MERGE", "The migratable resource is configured to be merged.", value: "merge"
      value "CONFLICT", "The migratable resource is in a conflict state.", value: "conflict"
      value "SKIP", "The migratable resource is configured to skip import.", value: "skip"

      # optimal (final) states
      # "SUCCESS" should include all the values of the states below it
      value "SUCCEEDED", "The migratable resource has been successfully migrated.", value: %w(exported imported mapped renamed merged skipped)
      value "EXPORTED", "The migratable resource has been successfully exported.", value: "exported"
      value "IMPORTED", "The migratable resource has been successfully imported.", value: "imported"
      value "MAPPED", "The migratable resource has been successfully mapped.", value: "mapped"
      value "RENAMED", "The migratable resource has been successfully renamed.", value: "renamed"
      value "MERGED", "The migratable resource has been successfully merged.", value: "merged"
      value "SKIPPED", "The migratable resource was not imported.", value: "skipped"

      # failed (final) states
      # "FAILED" should include all the values of the states below it
      value "FAILED", "The migratable resource failed to migrate.", value: %w(failed_export failed_import failed_map failed_rename failed_merge failed_skip)
      value "FAILED_EXPORT", "The migratable resource failed to export.", value: "failed_export"
      value "FAILED_IMPORT", "The migratable resource failed to import.", value: "failed_import"
      value "FAILED_MAP", "The migratable resource failed to map.", value: "failed_map"
      value "FAILED_RENAME", "The migratable resource failed to rename.", value: "failed_rename"
      value "FAILED_MERGE", "The migratable resource failed to merge.", value: "failed_merge"
      value "FAILED_SKIP", "The migratable resource failed to be skipped.", value: "failed_skip"
    end
  end
end
