# typed: strict
# frozen_string_literal: true

# This job will be executed only at GHES and will backfill the missing value for last_issued_at for oauth accesses table.
class GhesBackfillOauthAccessLastIssuedAtJob < ApplicationJob
  queue_as :apps_ghes_backfill

  INTERVAL = T.let(1.day, ActiveSupport::Duration)

  schedule interval: INTERVAL, condition: -> { GitHub.enterprise? }
  locked_by timeout: INTERVAL, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  BACKFILL_COMPLETED_KEY = "backfill_ghes_oauth_access_last_issued_at_completed"

  sig { void }
  def perform
    return unless GitHub.enterprise?
    return if Apps::KV.store.exists(BACKFILL_COMPLETED_KEY).value { false } # Skip if already completed

    index = Elastomer::Indexes::AuditLog.new
    hourly_updates = {}
    after_key = T.let(nil, T.untyped)

    loop do
      current_query = build_query(after_key)
      response = index.search(current_query)
      agg_results = response["aggregations"]["latest_action_per_oauth_access_id"]

      agg_results["buckets"].each do |result|
        source = result["latest_action"]["hits"]["hits"].first["_source"]
        next if source["action"] == "oauth_access.destroy"

        oauth_access_id = result["key"]["oauth_access_id"].to_i
        timestamp = source["@timestamp"] / 1000
        time = Time.at(timestamp)

        # Gets the floor of the hour
        hour_timestamp = Time.new(time.year, time.month, time.day, time.hour)

        hourly_updates[hour_timestamp] ||= []
        hourly_updates[hour_timestamp] << oauth_access_id
      end

      break unless after_key = agg_results["after_key"]

      GitHub.logger.info(
        "Processed batch with #{agg_results['buckets'].size} records",
        "gh.job.name" => self.class.name,
        "gh.job.action" => :perform,
      )
    end

    # Process updates by hour buckets
    hourly_updates.each do |hour_time, oauth_access_ids|
      GitHub.logger.info(
        "Processing #{oauth_access_ids.size} updates for hour: #{hour_time}",
        "gh.job.name" => self.class.name,
        "gh.job.action" => :perform,
      )

      with_write do
        OauthAccess
          .where(id: oauth_access_ids, last_issued_at: nil)
          .update_all(last_issued_at: hour_time)
      end
    end

    with_write do
      Apps::KV.store.set(BACKFILL_COMPLETED_KEY, Time.now.rfc3339)
    end
  end

  private

  sig { params(after_key: T.nilable(T::Hash[T.untyped, T.untyped])).returns(T::Hash[T.untyped, T.untyped]) }
  def build_query(after_key = nil)
    query = {
      query: {
        bool: {
          filter: [
            {
              terms: {
                action: [
                  "oauth_access.create",
                  "oauth_access.regenerate",
                  "oauth_access.destroy"
                ]
              }
            },
            {
              term: {
                "data.application_id": 0
              }
            },
            {
              term: {
                "data.application_type": "OauthApplication"
              }
            },
            {
              range: {
                "@timestamp": {
                  "gte": "now-1y"
                }
              }
            }
          ]
        }
      },
      aggs: {
        latest_action_per_oauth_access_id: {
          composite: {
            size: 1000,
            sources: [
              {
                oauth_access_id: {
                  terms: {
                    field: "data.oauth_access_id"
                  }
                }
              }
            ]
          },
          aggs: {
            latest_action: {
              top_hits: {
                sort: [
                  {
                    "@timestamp": {
                      order: "desc"
                    }
                  }
                ],
                _source: {
                  includes: ["action", "data.oauth_access_id", "@timestamp"]
                },
                size: 1
              }
            }
          }
        }
      }
    }

    # Add after_key for pagination if provided
    if after_key
      query[:aggs][:latest_action_per_oauth_access_id][:composite][:after] = after_key
    end

    query
  end
end
