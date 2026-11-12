# frozen_string_literal: true

module AdvisoryDB
  module Config
    # Please do not add configuration methods to this file.
    # Organize configuration methods in separate lib/advisory_db/config files.
  end
end

# Require all configuration files in the lib/advisory_db/config directory.
Dir[File.expand_path("config/*.rb", __dir__)].each { |f| require f }

# Add all configuration methods to the top-level AdvisoryDB namespace.
AdvisoryDB.extend(AdvisoryDB::Config)
