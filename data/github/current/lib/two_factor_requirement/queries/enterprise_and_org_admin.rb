# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class EnterpriseOrgAdmin < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        GitHub.flipper[:bulwark_steady_state_cohort_4].enabled?
      end

      def cohort_ctes(lookback_timestamp: nil)
        %Q(
          , orgs_with_repo AS (
            SELECT distinct U.id as org_id
            FROM hive.snapshots_presto.users U
            INNER JOIN hive.canonical.repositories_current R on R.owner_dotcom_id = U.id
            WHERE R.owner_type = 'Organization'
                AND R.is_spammy_owner = FALSE
          ),

          orgs_with_users AS (
              SELECT subject_id AS org_id
              FROM hive.snapshots_presto.abilities
              WHERE actor_type = 'User'
                  AND subject_type = 'Organization'
              GROUP BY subject_id
              HAVING count(actor_id) > 1
          ),

          edu_coupons AS (
            SELECT c.id
            FROM hive.snapshots_presto.coupons c
            WHERE c."group" IN ('education-individual', 'education-promo', 'education-org')
          ),

          edu_orgs AS (
            SELECT DISTINCT u.id as org_id
            FROM hive.snapshots_presto.coupon_redemptions cr
            INNER JOIN edu_coupons oc ON cr.coupon_id = oc.id
            INNER JOIN hive.snapshots_presto.users u ON u.id = cr.user_id
            WHERE u."type" = 'Organization' AND cr.expired = FALSE
          ),

          cohort_orgs AS (
            SELECT org_id
            from orgs_with_repo

            UNION

            SELECT org_id
            from orgs_with_users

            EXCEPT

            SELECT org_id
            FROM edu_orgs
          )
        )
      end

      # Builds a raw query for presto that finds users who are enterprise or organization admins.
      # Excludes organizations that have only 1 user or no repositories.
      # Always use `filtered_users` instead of `hive.snapshots_presto.users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          (
            SELECT
                DISTINCT A.actor_id AS id
            FROM
                hive.snapshots_presto.abilities A
                INNER JOIN filtered_users U on U.id = A.actor_id
                INNER JOIN cohort_orgs O ON O.org_id = A.subject_id
                AND A.subject_type = 'Organization'
            WHERE
                A.actor_type = 'User'
                AND A.action = 2
          )
          UNION
          (
            SELECT
              DISTINCT A.actor_id AS id
            FROM hive.snapshots_presto.abilities A
            INNER JOIN filtered_users U on U.id = A.actor_id
              AND A.subject_type = 'Business'
            WHERE
              A.actor_type = 'User'
              AND A.action = 2
              #{"AND (A.created_at > timestamp '#{lookback_timestamp}' OR A.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          )
        )
      end
    end
  end
end
