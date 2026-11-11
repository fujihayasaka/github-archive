# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class PackageEcosystemSerializer
      UNKNOWN_ECOSYSTEM_TOKEN = "unknown"

      # Initializes a serializer for the package ecosystem with the given name.
      #
      # name     - The String name for the package ecosystem.
      # _options - Unused. Exists solely to mimic the interface of
      #            ActiveModel::Serializer#initialize (https://git.io/JklN9).
      def initialize(name, _options = {})
        @name = name
      end

      def to_h
        {
          name: token.underscore.upcase,
          support: "BETA", # For now, everything is in beta for scheduled runs
          is_repository_access_supported: repository_access_supported?,
        }
      end

      def repository_access_supported?
        UpdateConfig::PACKAGE_MANAGERS_WITH_CODE_EXECUTION.exclude?(@name)
      end

      private

      def token
        ParseConfigFile.token_for(package_manager: @name)
      rescue KeyError
        UNKNOWN_ECOSYSTEM_TOKEN
      end
    end
  end
end
