# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class OpenSSFContributor < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      # Builds a raw query for presto that finds users who are Open Source Security Foundation (Open SSF) contributors limited by time.
      # Always use `filtered_users` instead of `#{self.users_table}`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          SELECT distinct(u.id) AS id
          FROM delta.snapshots.github_ballast_pushes p
            INNER JOIN filtered_users u on u.id = p.pusher_id
            WHERE p.repository_id IN (
              #{OPEN_SSF_REPO_IDS.join(',')}
            )
            #{"AND (p.created_at > timestamp '#{lookback_timestamp}' OR p.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
        )
      end
    end
  end
end
