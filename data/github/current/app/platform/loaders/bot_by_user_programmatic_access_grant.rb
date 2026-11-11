# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class BotByUserProgrammaticAccessGrant < Platform::Loader
      def self.load(user_programmatic_access_grant)
        return Promise.resolve(nil) unless user_programmatic_access_grant.present?

        self.for.load(user_programmatic_access_grant.id)
      end

      def fetch(user_programmatic_access_grant_ids)
        results = ProgrammaticAccessGrant.with_bot(User, ids: user_programmatic_access_grant_ids)

        bots_by_user_programmatic_grant_id = {}

        results.find_each do |grant|
          bots_by_user_programmatic_grant_id[grant.id] = grant.bot
        end

        bots_by_user_programmatic_grant_id
      end
    end
  end
end
