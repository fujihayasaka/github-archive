# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BotByOrganizationProgrammaticAccessGrant < Platform::Loader
      def self.load(organization_programmatic_access_grant)
        return Promise.resolve(nil) unless organization_programmatic_access_grant.present?

        self.for.load(organization_programmatic_access_grant.id)
      end

      def fetch(organization_programmatic_access_grant_ids)
        results = ProgrammaticAccessGrant.with_bot(Organization, ids: organization_programmatic_access_grant_ids)

        bots_by_organization_programmatic_grant_id = {}

        results.find_each do |grant|
          bots_by_organization_programmatic_grant_id[grant.id] = grant.bot
        end

        bots_by_organization_programmatic_grant_id
      end
    end
  end
end
