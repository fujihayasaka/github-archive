# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class RegistryRepoAdmin < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      def cohort_ctes(lookback_timestamp: nil)
        %Q(
          , repositories AS (
            SELECT id FROM #{self.repositories_table} WHERE id IN (
              #{NPM_PACKAGE_REPO_IDS.join(',')}
            )
            UNION ALL
            SELECT id FROM #{self.repositories_table} WHERE id IN (
              #{PYPI_REPO_IDS.join(',')}
            )
            UNION ALL
            SELECT id FROM #{self.repositories_table} WHERE id IN (
              #{RUBY_GEMS_REPO_IDS.join(',')}
            )
          ),
          direct_users as (
            SELECT DISTINCT a.actor_id AS id
            FROM #{self.abilities_table} a
              INNER JOIN filtered_users u on u.id = a.actor_id
              INNER JOIN repositories r on r.id = a.subject_id
            WHERE a.subject_type = 'Repository'
              AND a.action = 2
              AND a.actor_type = 'User'
              #{"AND (a.created_at > timestamp '#{lookback_timestamp}' OR a.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          ),
          indirect_users as(
            SELECT DISTINCT a.actor_id AS id
            FROM #{self.abilities_table} a
              INNER JOIN filtered_users u on u.id = a.actor_id
              INNER JOIN #{self.abilities_table} p ON p.actor_type = a.subject_type AND p.actor_id = a.subject_id
              INNER JOIN repositories r on r.id = p.subject_id
            WHERE a.actor_type = 'User' AND a.subject_type IN ('Team', 'Organization')
              AND p.actor_type IN ('Team', 'Organization')
              AND p.subject_type = 'Repository'
              AND p.action = 2
              #{"AND (a.created_at > timestamp '#{lookback_timestamp}' OR a.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          ),
          repo_owners as(
            SELECT DISTINCT owner_id AS id
            FROM #{self.repositories_table} r
            INNER JOIN filtered_users u ON u.id = r.owner_id
            INNER JOIN repositories n on n.id = r.id
            #{"AND (r.created_at > timestamp '#{lookback_timestamp}' OR r.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          )
        )
      end

      # Builds a raw query for presto that finds users who are registry repositories admins limited by time.
      # Always use `filtered_users` instead of `#{self.users_table}`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          SELECT id FROM repo_owners
          UNION
          SELECT id FROM direct_users
          UNION
          SELECT id FROM indirect_users
        )
      end
    end
  end
end
