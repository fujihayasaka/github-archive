# frozen_string_literal: true

# Dependabot-core has a no-op logger unless you configure one. This means logs
# in dependabot-core don't end up in splunk. We can set it to the rails logger,
# which conforms to the expected interface.

# we have a `dependabot/logger.rb` in both dependabot-core and our lib
# directory, with the lib one taking precedence, so we're going to explicitly
# load the logger from the gem cache

gem_name = "dependabot-common"
gem_version = Gem.loaded_specs[gem_name].version.to_s
gem_path = File.join(Gem.dir, "gems", "#{gem_name}-#{gem_version}")

# Build the path to the file you want to load
dependabot_logger_path = File.join(gem_path, "lib", "dependabot", "logger.rb")

# Load the file from the gem explicitly
load dependabot_logger_path

# Temporarily monkey patch to handle Rails 7.1 BroadcastLogger
# TODO: Remove this when dependabot-core supports BroadcastLogger natively
module Dependabot
  class << self
    alias original_logger= logger=

    def logger=(logger)
      # Handle Rails 7.1 BroadcastLogger by extracting a compatible logger
      if logger.is_a?(ActiveSupport::BroadcastLogger)
        # BroadcastLogger.broadcasts returns an array of loggers
        # Use the first one, or fall back to stdout logger
        compatible_logger = logger.broadcasts.first || Logger.new($stdout)
        compatible_logger.level = logger.level if compatible_logger.respond_to?(:level=)
        self.original_logger = compatible_logger
      else
        self.original_logger = logger
      end
    end
  end
end

Dependabot.logger = Rails.logger
