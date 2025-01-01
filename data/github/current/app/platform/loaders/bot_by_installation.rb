# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BotByInstallation < Platform::Loader
      def self.load(installation)
        case installation.class.to_s
        when "GlobalIntegrationInstallation"
          # A GlobalIntegrationInstalation is not an AR object,
          # so we can't perform the usual lookups.
          Promise.resolve(installation.bot)
        when "IntegrationInstallation",
             "ScopedIntegrationInstallation",
             "SiteScopedIntegrationInstallation"
          self.for(installation.class).load(installation.id)
        else
          Promise.resolve(nil)
        end
      end

      def initialize(installation_type)
        @installation_type = installation_type
      end

      def fetch(installation_ids)
        results = "::#{@installation_type}".constantize
          .includes(integration: [:bot])
          .where(id: installation_ids).index_by(&:id)

        bots_by_installation_id = {}

        results.each do |id, installation|
          bots_by_installation_id[id] = installation.bot
        end

        bots_by_installation_id
      end
    end
  end
end
