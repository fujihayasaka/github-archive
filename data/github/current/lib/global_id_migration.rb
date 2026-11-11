# typed: true
# frozen_string_literal: true

module GlobalIdMigration
  autoload :CLI, "global_id_migration/cli"
  autoload :DataDotQueryGenerator, "global_id_migration/data_dot_query_generator"
  autoload :Schedule, "global_id_migration/schedule"
  autoload :Metadata, "global_id_migration/metadata"
  autoload :ResultPrinter, "global_id_migration/result_printer"
  autoload :Formatting, "global_id_migration/formatting"
end
