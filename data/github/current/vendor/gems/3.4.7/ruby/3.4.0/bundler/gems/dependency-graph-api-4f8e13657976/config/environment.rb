# Load the Rails application.
require_relative "application"

Rails.application.configure do
  config.active_record.schema_migrations_table_name = "dg_schema_migrations"
  config.active_record.internal_metadata_table_name = "dg_ar_internal_metadata"

  config.aqueduct_app_name = "dependency-graph-api"
end

# Initialize the Rails application.
Rails.application.initialize!
