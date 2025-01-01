# typed: true
# frozen_string_literal: true

class Marketplace::ListingInsight < ApplicationRecord::Domain::Integrations
  self.table_name = "marketplace_listing_insights"

  # rubocop:todo Rails/InverseOf
  belongs_to :listing, class_name: "Marketplace::Listing", foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf

  validates :listing, :recorded_on, presence: true

  SUMMABLE_COLUMNS = %w(
    pageviews visitors new_purchases new_seats upgrades upgraded_seats
    downgrades downgraded_seats cancellations cancelled_seats mrr_recurring mrr_gained mrr_lost installs
    landing_uniques checkout_uniques new_free_subscriptions new_paid_subscriptions
    new_free_trial_subscriptions free_trial_conversions free_trial_cancellations
  )
  SUMMED_COLUMNS = SUMMABLE_COLUMNS.map { |col| "SUM(#{col}) AS #{col}" }.join(", ").freeze

  # These are offsets relative to a given end date used to find the beginning
  # of a time period for a Marketplace listing insights timeline:
  #
  # - :day goes back zero days (only today)
  # - :week goes back 6 days (7 days including today)
  # - :month goes back 29 days (30 days including today)
  PERIOD_OFFSET_MAPPING = { day: 0, week: 6, month: 29 }

  TRANSACTION_ACTIONS = %w(mp_purchased mp_changed mp_cancelled).freeze

  ALL_METRIC_TYPES = [:installation, :transaction, :traffic]

  scope :for_period, -> (period, end_date = self.latest_available_date) {
    end_date = self.latest_available_date if end_date > self.latest_available_date

    insights = order(:recorded_on)

    if period == :alltime
      insights.summed.grouped_by_month
    else
      insights.recorded_during(period, end_date)
    end
  }

  scope :recorded_during, -> (period, end_date) {
    offset = PERIOD_OFFSET_MAPPING[period]
    start_date = end_date - offset.days

    start_ts = start_date.strftime("%Y-%m-%d 00:00:00")
    end_ts = end_date.strftime("%Y-%m-%d 23:59:59")

    where("recorded_on >= ? AND recorded_on <= ?", start_ts, end_ts)
  }

  scope :summed, -> {
    select(SUMMED_COLUMNS).group(:marketplace_listing_id)
  }

  scope :grouped_by_month, -> {
    select("DATE_FORMAT(recorded_on, '%Y-%m') AS recording_period, marketplace_listing_id, recorded_on").
      where("recorded_on <= ?", self.latest_available_date.end_of_day).
      group("recording_period")
  }

  # Public: returns most recent date that Insights are available for. Our data sync is 1.5 days behind.
  def self.latest_available_date
    Date.current - 2.days
  end

  # Public: load all metrics for the insight's listing/date.
  def load_metrics(metric_types = nil)
    metric_types = Array(metric_types || default_metric_types)
    load_installation_metrics if metric_types.include?(:installation)
    load_transaction_metrics if metric_types.include?(:transaction)
    load_traffic_metrics if metric_types.include?(:traffic)
    self
  end

  def default_metric_types
    ALL_METRIC_TYPES
  end

  # Public: save all metrics for the insight's listing/date.
  def save_metrics!(metric_types = nil)
    metric_types = Array(metric_types || ALL_METRIC_TYPES)
    GitHub.logger.info("save_metrics", "gh.marketplace.metric.types" => metric_types)
    save_installation_metrics! if metric_types.include?(:installation)
    GitHub.logger.info("after installation metrics")
    save_transaction_metrics! if metric_types.include?(:transaction)
    GitHub.logger.info("after transaction metrics")
    save_traffic_metrics! if metric_types.include?(:traffic)
    GitHub.logger.info("after traffic metrics")
    self
  end

  # Public: load and save all metrics for the insight's listing/date.
  def update_metrics!(metric_types = nil)
    ActiveRecord::Base.connected_to(role: :reading) { load_metrics(metric_types) }
    save_metrics!(metric_types)
    self
  end

  def platform_type_name
    "MarketplaceListingInsight"
  end

  private

  # Private: load current installation metrics for the insight's listing/date.
  def load_installation_metrics
    app_installs = if T.must(listing).listable_is_integration?
      IntegrationInstallation.where(integration_id: T.must(listing).listable_id)
    elsif T.must(listing).listable_is_oauth_application?
      OauthAuthorization.where(application_id: T.must(listing).listable_id)
    end

    self.installs = T.must(app_installs).where(created_at: recording_day).count

    self
  end

  # Private: insert or update installation metrics for the insight's listing/date.
  def save_installation_metrics!
    sql_bindings = {
      marketplace_listing_id: marketplace_listing_id,
      installs: installs,
      recorded_on: recorded_on,
    }

    GitHub.logger.info("save_installation_metrics",
      { "gh.marketplace.listing.id" => marketplace_listing_id,
        "gh.marketplace.listing.install.count" => installs,
        "gh.marketplace.listing.recorded_on" => recorded_on
      })
    insert = %Q(
      INSERT INTO marketplace_listing_insights
        (marketplace_listing_id, recorded_on, created_at, updated_at, installs)
      VALUES
        (:marketplace_listing_id, :recorded_on, NOW(), NOW(), :installs)
      ON DUPLICATE KEY UPDATE
        installs = :installs,
        updated_at = NOW()
    )

    self.class.connection.insert(Arel.sql(insert, **sql_bindings))

    self
  end

  # Private: Array of listing plans belonging to this insight's listing.
  def plans
    @plans ||= T.must(listing).listing_plans.index_by(&:id)
  end

  # Private: Transactions with a timestamp on this insight's recording day, involving a plan
  #          belonging to this insight's listing.
  #
  #          Grouped by action, returns a Hash of action => Array of transactions.
  def marketplace_transactions
    @marketplace_transactions ||= begin
      transactions = Transaction.
        for_subscribables(plans.values).
        where(active_listing: true).
        where(action: TRANSACTION_ACTIONS).
        where(timestamp: recording_day)

      Hash.new([]).merge!(transactions.group_by(&:action))
    end
  end

  # Private: load current transaction metrics for the insight's listing/date.
  def load_transaction_metrics
    free_plan_ids = plans.keys.select { |id| !plans[id].paid? }
    paid_plan_ids = plans.keys.select { |id| plans[id].paid? }
    free_trial_plan_ids = plans.keys.select { |id| plans[id].has_free_trial? }

    # New purchase metrics are:
    #   - new_purchases: count for 'mp_purchased' action [will be deprecated]
    #   - new_seats: sum of current_subscribable_quantity for 'mp_purchased' action
    #   - new_free_subscriptions count of new subscriptions to free plans
    #   - new_paid_subscriptions count of new subscriptions to paid plans
    #   - new_free_trial_subscriptions of new subscriptions to paid plans with free trials
    new_subscriptions = marketplace_transactions["mp_purchased"].reject { |tx| tx.current_subscribable_id.nil? }
    self.new_purchases = new_subscriptions.count
    self.new_free_subscriptions = new_subscriptions.count { |tx| tx.current_subscribable_id.in?(free_plan_ids) }
    self.new_paid_subscriptions = new_subscriptions.count { |tx| tx.current_subscribable_id.in?(paid_plan_ids) }
    self.new_free_trial_subscriptions = new_subscriptions.count { |tx| tx.current_subscribable_id.in?(free_trial_plan_ids) }
    self.new_seats = new_subscriptions.inject(0) { |seats, tx| seats += tx.current_subscribable_quantity || 0 }

    self.mrr_gained = mrr_gained_for_listing

    # Cancellation metrics are:
    #   - count for 'mp_cancelled' action
    #   - sum of old_listing_plan_quantity for 'mp_cancelled' action
    cancelled_subscriptions = marketplace_transactions["mp_cancelled"].reject { |tx| tx.old_subscribable_id.nil? }
    self.cancellations = cancelled_subscriptions.count
    self.cancelled_seats = cancelled_subscriptions.inject(0) { |seats, tx| seats += tx.old_subscribable_quantity || 0 }
    self.mrr_lost = cancelled_subscriptions.inject(0) do |mrr, tx|
      plan = plans[tx.old_subscribable_id]

      if plan.per_unit?
        mrr += (plan.monthly_price_in_cents * tx.current_subscribable_quantity)
      else
        mrr += plan.monthly_price_in_cents
      end
    end

    # Plan change metrics are:
    #   - upgrades: count for 'mp_changed' action with a higher monthly/plan cost
    #   - upgraded seats: count for 'mp_changed' action with a higher monthly/plan cost
    #   - downgrades: count for 'mp_changed' action with a lower monthly/plan cost
    #   - downgraded seats: count for 'mp_changed' action with a lower monthly/plan cost
    #
    # QUESTION: what about no change - are those transactions invisible to insights?
    self.upgrades = 0
    self.upgraded_seats = 0
    self.downgrades = 0
    self.downgraded_seats = 0
    marketplace_transactions["mp_changed"].each do |tx|
      # For certain types of plan changes (eg. switching to yearly billing) the
      # Transaction record has no old_subscribable_id. That should have no impact
      # on insights and should be safe to skip here.
      next unless tx.old_subscribable_id && tx.current_subscribable_id

      old_plan = plans[tx.old_subscribable_id]
      new_plan = plans[tx.current_subscribable_id]

      old_monthly = old_plan.monthly_price_in_cents
      old_monthly *= tx.old_subscribable_quantity if old_plan.per_unit?
      new_monthly = new_plan.monthly_price_in_cents
      new_monthly *= tx.current_subscribable_quantity if new_plan.per_unit?

      if old_monthly > new_monthly
        self.downgrades += 1
        self.downgraded_seats = tx.old_subscribable_quantity
        self.mrr_lost += (old_monthly - new_monthly)
      elsif old_monthly < new_monthly
        self.upgrades += 1
        self.upgraded_seats = tx.current_subscribable_quantity
        self.mrr_gained += (new_monthly - old_monthly)
      end
    end

    # Monthly recurring revenue from ongoing subscriptions is:
    #   - the sum of all billing transaction line items
    #     * billed on this insight's recording day
    #     * associated with one of this listing's plans
    #     * from transactions of type "recurring-charge"
    self.mrr_recurring = Integer(Billing::BillingTransaction::LineItem.marketplace.
      joins(:billing_transaction).
      where("billing_transaction_line_items.amount_in_cents > 0").
      where(
        billing_transactions: {
          transaction_type: "recurring-charge",
          last_status: Billing::BillingTransactionStatuses::SUCCESS[:settled],
        },
        billing_transaction_line_items: {
          subscribable_id: plans.keys,
          created_at: recording_day,
        },
      ).
      sum(:amount_in_cents))

    # Free trial subscription metrics are:
    #   - free_trial_conversions: count of free trials which ended with an active subscription
    #                             to the trial plan or to another paid plan.
    #   - free_trial_cancellations: count of free trials which ended without an active
    #                               subscription to a paid plan.
    if free_trial_plan_ids.any?
      binds = {
        plan_ids: free_trial_plan_ids,
        beginning_of_recording_day: recording_day.first,
        end_of_recording_day: recording_day.last,
        old_subscribable_type: Transaction.old_subscribable_types[T.must(Marketplace::ListingPlan.name)],
        current_subscribable_type: Transaction.current_subscribable_types[T.must(Marketplace::ListingPlan.name)],
      }

      ft_conversion_query = %Q(
        SELECT count(*) FROM transactions t
          JOIN marketplace_listing_plans op ON (t.old_subscribable_id=op.id AND t.old_subscribable_type=:old_subscribable_type) /* cross-schema-domain-query-exempted */
          JOIN marketplace_listing_plans np ON (t.current_subscribable_id=np.id AND t.current_subscribable_type=:current_subscribable_type)
          JOIN subscription_items si ON (si.subscribable_id=op.id AND si.subscribable_type=#{Billing::SubscriptionItem::MARKETPLACE_SUBSCRIBABLE_TYPE})
          JOIN plan_subscriptions ps ON (si.plan_subscription_id=ps.id and t.user_id=ps.user_id)
        WHERE
          t.action="mp_changed" AND t.old_subscribable_id IN (:plan_ids) AND t.old_subscribable_type=:old_subscribable_type AND t.active_listing = 1 AND
          t.timestamp BETWEEN :beginning_of_recording_day AND :end_of_recording_day AND
          ((t.old_subscribable_id = t.current_subscribable_id AND t.old_subscribable_quantity = t.current_subscribable_quantity) OR
           (np.monthly_price_in_cents > 0 AND si.free_trial_ends_on >= :end_of_recording_day))
      )
      results = Transaction.connection.select_rows(Arel.sql(ft_conversion_query, **binds))
      self.free_trial_conversions = results.first.first

      ft_cancellation_query = %Q(
        SELECT count(*) FROM transactions t
          JOIN marketplace_listing_plans op ON (t.old_subscribable_id=op.id AND t.old_subscribable_type=:old_subscribable_type) /* cross-schema-domain-query-exempted */
          LEFT JOIN marketplace_listing_plans np ON (t.current_subscribable_id=np.id AND t.current_subscribable_type=:current_subscribable_type)
          JOIN subscription_items si ON (si.subscribable_id=op.id AND si.subscribable_type=#{Billing::SubscriptionItem::MARKETPLACE_SUBSCRIBABLE_TYPE})
          JOIN plan_subscriptions ps ON (si.plan_subscription_id=ps.id AND t.user_id=ps.user_id)
        WHERE
          t.old_subscribable_id IN (:plan_ids) AND t.active_listing = 1 AND
          t.timestamp BETWEEN :beginning_of_recording_day AND :end_of_recording_day AND
          si.free_trial_ends_on >= :beginning_of_recording_day AND
          (action = "mp_cancelled" OR (action = "mp_changed" AND np.monthly_price_in_cents = 0))
      )
      results = Transaction.connection.select_rows(Arel.sql(ft_cancellation_query, **binds))
      self.free_trial_cancellations = results.first.first
    end

    self
  end

  # Calculate mrr gained without cross schema domain join
  def mrr_gained_for_listing
    ids_with_multipliers = Billing::BillingTransaction::LineItem
      .joins(:billing_transaction)
      .where(
        billing_transactions: {
          transaction_type: "prorate-charge",
          last_status: Billing::BillingTransactionStatuses::SUCCESS[:settled],
        },
        billing_transaction_line_items: { created_at: recording_day },
      )
      .marketplace
      .where(subscribable_id: plans.keys)
      .group(:subscribable_id)
      .count

    Marketplace::ListingPlan.where(id: ids_with_multipliers.keys).sum do |listing_plan|
      listing_plan.monthly_price_in_cents * T.must(ids_with_multipliers[listing_plan.id])
    end
  end

  # Private: insert or update transaction metrics for the insight's listing/date.
  def save_transaction_metrics!
    sql_bindings = {
      marketplace_listing_id: marketplace_listing_id,
      recorded_on: recorded_on,
      new_purchases: new_purchases,
      new_seats: new_seats,
      new_free_subscriptions: new_free_subscriptions,
      new_paid_subscriptions: new_paid_subscriptions,
      new_free_trial_subscriptions: new_free_trial_subscriptions,
      upgrades: upgrades,
      upgraded_seats: upgraded_seats,
      downgrades: downgrades,
      downgraded_seats: downgraded_seats,
      cancellations: cancellations,
      cancelled_seats: cancelled_seats,
      mrr_gained: mrr_gained,
      mrr_lost: mrr_lost,
      mrr_recurring: mrr_recurring,
      free_trial_conversions: free_trial_conversions,
      free_trial_cancellations: free_trial_cancellations,
    }

    GitHub.logger.info("save_transaction_metrics",
      { "gh.marketplace.listing.id" => marketplace_listing_id,
        "gh.marketplace.recorded_on" => recorded_on,
        "gh.marketplace.new_purchases" => new_purchases
      })

    insert = %Q(
      INSERT INTO marketplace_listing_insights
        (marketplace_listing_id, recorded_on, created_at, updated_at, new_purchases, new_seats,
         new_free_subscriptions, new_paid_subscriptions, new_free_trial_subscriptions,
         upgrades, upgraded_seats, downgrades, downgraded_seats,
         cancellations, cancelled_seats, mrr_gained, mrr_lost, mrr_recurring,
         free_trial_conversions, free_trial_cancellations)
      VALUES
        (:marketplace_listing_id, :recorded_on, NOW(), NOW(), :new_purchases, :new_seats,
         :new_free_subscriptions, :new_paid_subscriptions, :new_free_trial_subscriptions,
         :upgrades, :upgraded_seats, :downgrades, :downgraded_seats,
         :cancellations, :cancelled_seats, :mrr_gained, :mrr_lost, :mrr_recurring,
         :free_trial_conversions, :free_trial_cancellations)
      ON DUPLICATE KEY UPDATE
        new_purchases = :new_purchases,
        new_seats = :new_seats,
        new_free_subscriptions = :new_free_subscriptions,
        new_paid_subscriptions = :new_paid_subscriptions,
        new_free_trial_subscriptions = :new_free_trial_subscriptions,
        upgrades = :upgrades,
        upgraded_seats = :upgraded_seats,
        downgrades = :downgrades,
        downgraded_seats = :downgraded_seats,
        cancellations = :cancellations,
        cancelled_seats = :cancelled_seats,
        mrr_gained = :mrr_gained,
        mrr_lost = :mrr_lost,
        mrr_recurring = :mrr_recurring,
        free_trial_conversions = :free_trial_conversions,
        free_trial_cancellations = :free_trial_cancellations,
        updated_at = NOW()
    )

    self.class.connection.insert(Arel.sql(insert, **sql_bindings))

    self
  end

  # Private: load current traffic metrics for the insight's listing/date.
  # IMPORTANT! If changing how one of the fields is calculated, make sure to update the
  # `UpdateMarketplaceTrafficInsightsJob` method to match the new logic.
  def load_traffic_metrics
    generic_query = %Q(
      SELECT
        COUNT(marketplace_events.event_id ) AS "marketplace_events.count",
        COUNT(DISTINCT marketplace_events.cid ) AS "marketplace_events.count_distinct_users"
      FROM hive.snapshots_presto.marketplace_listings  AS marketplace_listings
      LEFT JOIN hive.service_analytics.marketplace_events  AS marketplace_events ON marketplace_listings.id = marketplace_events.marketplace_listing_id

      WHERE
        ( marketplace_listings.id = #{marketplace_listing_id} ) AND
        ( marketplace_events.event_type = 'page_view' ) AND
        ( marketplace_events."time" >= (TIMESTAMP '#{recorded_on.strftime("%F")}') AND marketplace_events."time" < (TIMESTAMP '#{(recorded_on + 1.day).strftime("%F")}') )
    )

    _, rows = GitHub.trino.run(generic_query)

    traffic_insights = rows.first
    if traffic_insights
      self.pageviews = traffic_insights[0]
      self.visitors = traffic_insights[1]
    end

    landing_query = %Q(
      SELECT
        COUNT(DISTINCT marketplace_events.cid ) AS "marketplace_events.count_distinct_users"
      FROM hive.snapshots_presto.marketplace_listings  AS marketplace_listings
      LEFT JOIN hive.service_analytics.marketplace_events  AS marketplace_events ON marketplace_listings.id = marketplace_events.marketplace_listing_id

      WHERE
        ( marketplace_listings.id = #{marketplace_listing_id} ) AND
        ( marketplace_events.event_type = 'page_view' ) AND
        ( REGEXP_LIKE(marketplace_events.page, '/marketplace/#{T.must(listing).slug}(\\?|\$)') ) AND
        ( marketplace_events."time" >= (TIMESTAMP '#{recorded_on.strftime("%F")}') AND marketplace_events."time" < (TIMESTAMP '#{(recorded_on + 1.day).strftime("%F")}') )
    )
    _, rows = GitHub.trino.run(landing_query)

    traffic_insights = rows.first
    self.landing_uniques = traffic_insights[0] if traffic_insights

    checkout_query = %Q(
      SELECT
        COUNT(DISTINCT marketplace_events.cid ) AS "marketplace_events.count_distinct_users"
      FROM hive.snapshots_presto.marketplace_listings  AS marketplace_listings
      LEFT JOIN hive.service_analytics.marketplace_events  AS marketplace_events ON marketplace_listings.id = marketplace_events.marketplace_listing_id

      WHERE
        ( marketplace_listings.id = #{marketplace_listing_id} ) AND
        ( marketplace_events.event_type = 'page_view' ) AND
        ( marketplace_events.page like '%/marketplace/#{T.must(listing).slug}/order%' ) AND
        ( marketplace_events."time" >= (TIMESTAMP '#{recorded_on.strftime("%F")}') AND marketplace_events."time" < (TIMESTAMP '#{(recorded_on + 1.day).strftime("%F")}') )
    )
    _, rows = GitHub.trino.run(checkout_query)

    traffic_insights = rows.first
    self.checkout_uniques = traffic_insights[0] if traffic_insights

    self
  end

  # Private: insert or update traffic metrics for the insight's listing/date.
  def save_traffic_metrics!
    sql_bindings = {
      marketplace_listing_id: marketplace_listing_id,
      pageviews: pageviews,
      visitors: visitors,
      landing_uniques: landing_uniques,
      checkout_uniques: checkout_uniques,
      recorded_on: recorded_on,
    }

    GitHub.logger.info("save_traffic_metrics",
      { "gh.marketplace.listing.id" => marketplace_listing_id,
        "gh.marketplace.pageviews" => pageviews,
        "gh.marketplace.visitors" => visitors
      })

    insert = %Q(
      INSERT INTO marketplace_listing_insights
        (marketplace_listing_id, recorded_on, created_at, updated_at, pageviews, visitors, landing_uniques, checkout_uniques)
      VALUES
        (:marketplace_listing_id, :recorded_on, NOW(), NOW(), :pageviews, :visitors, :landing_uniques, :checkout_uniques)
      ON DUPLICATE KEY UPDATE
        pageviews = :pageviews,
        visitors = :visitors,
        landing_uniques = :landing_uniques,
        checkout_uniques = :checkout_uniques,
        updated_at = NOW()
    )

    self.class.connection.insert(Arel.sql(insert, **sql_bindings))

    self
  end

  def recording_day
    @recording_day ||= Range.new(
      recorded_on.strftime("%Y-%m-%d 00:00:00"),
      recorded_on.strftime("%Y-%m-%d 23:59:59"),
    )
  end
end
