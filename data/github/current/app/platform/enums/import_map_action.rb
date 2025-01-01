# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ImportMapAction < Platform::Enums::Base
      description "What action to take when performing an import migration."

      feature_flag :gh_migrator_import_to_dotcom

      value "MAP", "Map a record for import with an existing record.", value: :map
      value "MERGE", "Merge a record for import with an existing record.", value: :merge
      value "RENAME", "Rename a record for import as a new record.", value: :rename
      value "IMPORT", "Import a record as a new record.", value: :import
      value "SKIP", "Skip importing a record.", value: :skip
      value "CONFLICT", "Forced conflict.", value: :conflict
    end
  end
end
