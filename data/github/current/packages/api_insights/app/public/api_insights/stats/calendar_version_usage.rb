# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  # Queries the user materialized view to find users who have called the
  # REST API. Returns typed row structs with just the actor identifier
  # (and the tenant identifier in Proxima).
  #
  # The materialized view is no longer grouped by API version: a wave of
  # deprecation emails goes out to every user that has ever made an API
  # call, gated per-version by the ActionRestraint dedup key in the
  # cohort job. The email itself is generic — see ApiVersioning::
  # DeprecationMailer.
  #
  # Cohort methods:
  #   .users(offset:, batch_size:)
  #   .users_count
  #   .user_for_actor(actor_id:)
  class CalendarVersionUsage
    USER_MV = "APIINSIGHTS_version_usage_user_v2"

    DEFAULT_BATCH_SIZE = 1000

    class UserUsageRow < T::Struct
      const :actor_id, Integer
      # Tenant that owns the row in Proxima. Present when the source
      # materialized view summarizes by tenant_id (Proxima); absent on
      # dotcom, where the MV has no tenant_id column and the field stays
      # nil. Consumers use this to scope per-row processing (e.g. setting
      # GitHub::CurrentTenant before rendering tenant-aware mailer URLs).
      const :tenant_id, T.nilable(Integer)
    end

    sig do
      params(
        offset: Integer,
        batch_size: Integer,
      ).returns(T::Array[UserUsageRow])
    end
    def self.users(offset: 0, batch_size: DEFAULT_BATCH_SIZE)
      kql = <<~KQL
        materialized_view("#{USER_MV}")
        | where actor_id > offset_id
        | top batch_limit by actor_id asc
      KQL

      rows = execute(kql, {
        "offset_id" => offset,
        "batch_limit" => batch_size,
      })

      rows.map do |hash|
        UserUsageRow.new(
          actor_id: to_int(hash["actor_id"]),
          tenant_id: to_nilable_int(hash["tenant_id"]),
        )
      end
    end

    # Single-actor variant used by the deprecation notification jobs when
    # processing a targeted actor (e.g. for partial-failure recovery or
    # operator-targeted re-sends) instead of paging through the full cohort.
    # Returns an array of 0 or 1 rows so callers can reuse the same per-row
    # processing loop as the batched method above.
    sig do
      params(
        actor_id: Integer,
      ).returns(T::Array[UserUsageRow])
    end
    def self.user_for_actor(actor_id:)
      kql = <<~KQL
        materialized_view("#{USER_MV}")
        | where actor_id == target_actor_id
        | take 1
      KQL

      rows = execute(kql, {
        "target_actor_id" => actor_id,
      })

      rows.map do |hash|
        UserUsageRow.new(
          actor_id: to_int(hash["actor_id"]),
          tenant_id: to_nilable_int(hash["tenant_id"]),
        )
      end
    end

    sig { returns(Integer) }
    def self.users_count
      kql = <<~KQL
        materialized_view("#{USER_MV}")
        | count
      KQL
      rows = execute(kql, {})
      rows.first&.fetch("Count", 0).to_i
    end

    class << self
      private

      sig { params(kql: String, params: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, T.untyped]]) }
      def execute(kql, params)
        dataset = KustoClientProvider.query(
          GitHub.api_insights_kusto_database_name,
          kql,
          params,
          source: "calendar_version_usage",
        )

        columns = dataset.primary_result_table.columns
        dataset.primary_result_table.rows.map do |row|
          columns.each_with_index.each_with_object({}) do |(col, i), h|
            h[col.name] = row[i]
          end
        end
      rescue Kusto::Error => e
        GitHub.dogstats.increment("api_insights.calendar_version_usage.error", tags: ["error:#{e.class.name}"])
        raise
      end

      sig { params(value: T.untyped).returns(Integer) }
      def to_int(value)
        value.to_i
      end

      # Nil-preserving counterpart to to_int, used for columns that may be
      # absent from the row hash entirely (e.g. tenant_id on dotcom, where
      # the materialized view does not project it). Distinct from to_int so
      # callers don't silently turn missing values into 0.
      sig { params(value: T.untyped).returns(T.nilable(Integer)) }
      def to_nilable_int(value)
        return nil if value.nil?

        value.to_i
      end
    end
  end
end
