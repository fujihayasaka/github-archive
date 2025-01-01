# frozen_string_literal: true

# Require all configuration files in the config/instrumentation directory.
Dir[File.expand_path("instrumentation/*.rb", __dir__)].each { |f| require f }
