# typed: strict
# frozen_string_literal: true

class UpdateMarketplaceTrafficInsightsJob < ApplicationJob
  queue_as :site_stats

  sig { params(date: Date).void }
  def perform(date)
    public_states = Marketplace::Listing.publicly_listed_state_values

    # grab traffic data for all public listings
    # IMPORTANT! If changing how one of the fields is calculated, make sure to update the
    # `Marketplace::ListingInsight#load_traffic_metrics` method to match the new logic.
    traffic_query = <<~SQL
      SELECT
        marketplace_listings.id,
        COUNT(marketplace_events.event_id) AS pageviews,
        COUNT(DISTINCT marketplace_events.cid) AS visitors,
        COUNT(DISTINCT CASE
          WHEN REGEXP_LIKE(marketplace_events.page, '/marketplace/[^/]+(\\?|$)')
          THEN marketplace_events.cid
          ELSE NULL
        END) AS landing_uniques,
        COUNT(DISTINCT CASE
          WHEN marketplace_events.page LIKE '%/order/%'
          THEN marketplace_events.cid
          ELSE NULL
        END) AS checkout_uniques
      FROM hive.snapshots_presto.marketplace_listings AS marketplace_listings
      LEFT JOIN hive.service_analytics.marketplace_events AS marketplace_events
        ON marketplace_listings.id = marketplace_events.marketplace_listing_id
      WHERE
        marketplace_listings.state IN (#{public_states.join(', ')})
        AND marketplace_events.event_type = 'page_view'
        AND marketplace_events."time" >= (TIMESTAMP '#{date.strftime("%F")}')
        AND marketplace_events."time" < (TIMESTAMP '#{(date + 1.day).strftime("%F")}')
      GROUP BY marketplace_listings.id
    SQL

    _, rows = GitHub.trino.run(traffic_query)

    sql_mapping = rows.map do |row|
      {
        marketplace_listing_id: row[0].to_i,
        pageviews: row[1],
        visitors: row[2],
        landing_uniques: row[3],
        checkout_uniques: row[4],
        recorded_on: date
      }
    end

    with_write do
      # rubocop:disable GitHub/UpsertAll
      Marketplace::ListingInsight.upsert_all(
        sql_mapping,
        update_only: [:pageviews, :visitors, :landing_uniques, :checkout_uniques],
      )
      # rubocop:enable GitHub/UpsertAll
    end
  end
end
