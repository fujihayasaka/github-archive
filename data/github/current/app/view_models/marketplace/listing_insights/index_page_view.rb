# typed: true
# frozen_string_literal: true

module Marketplace::ListingInsights
  class IndexPageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActiveSupport::NumberHelper

    delegate :name, :slug, :published_free_plans?, to: :listing, prefix: true

    attr_reader :listing, :insights, :period, :period_offset

    def initialize(listing:, period:, current_user: nil, user_session: nil)
      @period = period
      @period_offset = Marketplace::ListingInsight::PERIOD_OFFSET_MAPPING[@period]
      @listing = listing
      @insights = listing.insights.for_period(period).to_a.first(100)
    end

    def insights_available?
      insights.present?
    end

    def listing_has_free_trials?
      return @listing_has_free_trials if defined? @listing_has_free_trials

      @listing_has_free_trials = listing.listing_plans.with_published_state.where(has_free_trial: true).any?
    end

    def listing_has_paid_plans?
      listing.paid?
    end

    def listing_has_multiple_plan_types?
      listing_has_paid_plans? && listing_published_free_plans?
    end

    def period_menu_options
      @period_menu_options ||= [
        { title: "Past Day", value: :day },
        { title: "Past Week", value: :week },
        { title: "Past Month", value: :month },
        { title: "All-time", value: :alltime },
      ]
    end

    def selected_period_title
      period_menu_options.find { |option| option[:value] == period }[:title]
    end

    def current_period_stats
      @current_period_stats ||= PeriodStats.new(insights)
    end

    # Public: Calculates the statistics for the previous period. If current Period is a Week. It grabs data for the week prior.
    def previous_period_stats
      return @previous_period_stats if @previous_period_stats

      previous_insights = listing.insights.for_period(period, (insights.first.recorded_on - 1.day)).to_a.first(100)
      @previous_period_stats = PeriodStats.new(previous_insights)
    end

    def period_end_date
      insights.last.recorded_on
    end

    def period_start_date
      return @period_start_date if @period_start_date

      if period == :alltime
        earliest_insight = insights.first
        @period_start_date = earliest_insight.present? ? earliest_insight.recorded_on.beginning_of_month : period_end_date
      else
        @period_start_date = (period_end_date - period_offset)
      end
    end

    def show_previous_period_comparison?
      insights.any? && [:day, :week, :month].include?(period)
    end

    def show_traffic_graph?
      [:week, :month, :alltime].include? period
    end

    def conversion_funnel_step_1_percent
      return if current_period_stats.total_landing_uniques.zero?
      "#{calculate_percentage(current_period_stats.total_checkout_uniques, current_period_stats.total_landing_uniques).to_i}%"
    end

    def conversion_funnel_step_2_percent
      return if current_period_stats.total_checkout_uniques.zero?
      "#{calculate_percentage(current_period_stats.total_new_paid_subscriptions, current_period_stats.total_checkout_uniques).to_i}%"
    end

    def conversion_funnel_step_2_percent_for_all_subscriptions
      number_to_percentage(
        calculate_percentage(
          sum_of_new_subscriptions,
          current_period_stats.total_checkout_uniques,
        ),
        precision: 0,
      )
    end

    def conversion_funnel_step_3_percent_for_free_trial_conversions
      number_to_percentage(
        calculate_percentage(
          current_period_stats.total_new_free_trial_conversions,
          current_period_stats.total_free_trial_results,
        ),
        precision: 1,
      )
    end

    def sum_of_new_subscriptions
      @sum_of_new_subscriptions ||= new_subscriptions.sum(&:value)
    end

    def sorted_new_subscriptions
      new_subscriptions.sort_by(&:value)
    end

    def formatted_subscription_percentage(metric)
      number_to_percentage(
        metric.percentage_in(scale: true_subscription_percentage_scale),
        precision: 1,
      )
    end

    def bar_width_scale
      @_bar_width_scale ||= GitHub::LinearScale.scale!(
        [0, max_number_of_subscriptions],
        [MIN_BAR_WIDTH, 100.0],
      )
    end

    def has_pending_installations?
      total_pending_installations > 0
    end

    def total_subscribed_customers
      return @total_subscribed_customers if defined? @total_subscribed_customers

      @total_subscribed_customers = listing.subscription_items.active.count
    end

    def total_pending_installations
      return @total_pending_installations if defined? @total_pending_installations

      @total_pending_installations = listing.subscription_items.active.not_installed.count
    end

    def pending_installations_percentage
      "#{calculate_percentage(total_pending_installations, total_subscribed_customers).round}%"
    end

    def pending_installations_tooltip
      "#{pending_installations_percentage} of #{total_subscribed_customers} subscribed customers"
    end

    private

    MIN_BAR_WIDTH = 5.0
    private_constant :MIN_BAR_WIDTH

    def true_subscription_percentage_scale
      @_true_percentage_scale ||= GitHub::LinearScale.scale!(
        [0, sum_of_new_subscriptions],
        [0.0, 100.0],
      )
    end

    def new_subscriptions
      @_new_subscriptions ||=
        begin
          subscriptions = []

          if listing_published_free_plans?
            subscriptions << SubscriptionMetric.new("orange", "color-fg-severe", "free", current_period_stats.total_new_free_subscriptions)
          end

          if listing_has_paid_plans?
            subscriptions << SubscriptionMetric.new("green", "color-fg-success", "paid", current_period_stats.total_new_paid_subscriptions_excluding_free_trials)

            if listing_has_free_trials?
              subscriptions << SubscriptionMetric.new("yellow", "color-fg-attention", "free trial", current_period_stats.total_new_free_trial_subscriptions)
            end
          end

          subscriptions
        end
    end

    def max_number_of_subscriptions
      @_max_subscriptions ||= new_subscriptions.max_by(&:value).value
    end

    def min_number_of_subscriptions
      @_min_subscriptions ||= new_subscriptions.min_by(&:value).value
    end

    def calculate_percentage(numerator, denominator)
      return 0 if denominator.zero?
      (numerator.to_f / denominator.to_f) * 100
    end

    class SubscriptionMetric
      BAR_WIDTH_FOR_NO_SUBSCRIPTIONS = 1.0

      attr_reader :bar_color, :legend_color, :pricing_model, :value

      def initialize(bar_color, legend_color, pricing_model, value)
        @bar_color = bar_color
        @legend_color = legend_color
        @pricing_model = pricing_model
        @value = value
      end

      def bar_width(scale:)
        if value.positive?
          percentage_in(scale: scale)
        else
          BAR_WIDTH_FOR_NO_SUBSCRIPTIONS
        end
      end

      def percentage_in(scale:)
        scale.call(value)
      end
    end

    class PeriodStats
      attr_reader :insights, :total_pageviews, :total_visitors, :total_subscription_value,
        :total_landing_uniques, :total_checkout_uniques, :total_new_paid_subscriptions,
        :total_new_free_subscriptions, :total_new_free_trial_subscriptions,
        :total_new_free_trial_conversions, :total_new_free_trial_cancellations, :total_free_trial_results

      def initialize(insights)
        @insights = insights
        @total_new_paid_subscriptions = total_for(:new_paid_subscriptions)
        @total_new_free_subscriptions = total_for(:new_free_subscriptions)
        @total_new_free_trial_subscriptions = total_for(:new_free_trial_subscriptions)
        @total_new_free_trial_conversions = total_for(:free_trial_conversions)
        @total_new_free_trial_cancellations = total_for(:free_trial_cancellations)
        @total_free_trial_results = @total_new_free_trial_conversions + @total_new_free_trial_cancellations
        @total_subscription_value = (total_for(:mrr_gained) + total_for(:mrr_recurring)) / 100
        @total_visitors = ad_block_total_for(:visitors)
        @total_pageviews = ad_block_total_for(:pageviews)
        @total_landing_uniques = ad_block_total_for(:landing_uniques)
        @total_checkout_uniques = ad_block_total_for(:checkout_uniques)
      end

      def total_new_paid_subscriptions_excluding_free_trials
        total_new_paid_subscriptions_including_conversions - total_new_free_trial_subscriptions
      end

      private

      def total_for(attribute)
        return 0 unless insights.any?

        insights.map do |insight|
          insight.send(attribute)
        end.inject(0, :+)
      end

      def ad_block_total_for(attribute)
        (total_for(attribute) * MarketplaceListingInsightsController::AD_BLOCKER_MULTIPLIER).to_i
      end

      def total_new_paid_subscriptions_including_conversions
        total_new_paid_subscriptions + total_new_free_trial_conversions
      end
    end
  end
end
