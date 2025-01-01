# typed: strict
# frozen_string_literal: true

module Stafftools
  module SponsorsHelper
    extend T::Sig
    include ActionView::Helpers
    include ApplicationHelper

    LISTING_SORT_OPTIONS = T.let({
      "most_recent_status_change" => "Most recent status change",
      "most_recent_published" => "Most recently published",
      "most_recent_approval_requested" => "Most recently submitted for approval",
      "most_recent" => "Most recent waitlist time",
      "newest_account_first" => "Most recently created account",
      "most_recent_payout" => "Most recent payout",
      "oldest_status_change" => "Oldest status change",
      "oldest_published" => "Oldest published",
      "approval_requested_at" => "Oldest submitted for approval",
      "oldest_first" => "Oldest waitlist time",
      "oldest_account_first" => "Oldest account age",
      "least_recent_payout" => "Least recent payout",
    }.freeze, T::Hash[String, String])

    sig { params(filter_key: String, filter_value: T.any(T::Array[String], String)).returns(String) }
    def sponsors_member_applied_filter_test_selector(filter_key, filter_value)
      str_filter_value = if filter_value.respond_to?(:join)
        T.unsafe(filter_value).join(",")
      else
        filter_value
      end
      "applied-filter-#{filter_key}-#{str_filter_value}"
    end

    sig { params(stripe_customer_id: T.nilable(String)).returns(T.nilable(String)) }
    def stripe_customer_url(stripe_customer_id)
      return if stripe_customer_id.blank?

      if Rails.env.production?
        "https://dashboard.stripe.com/customers/#{stripe_customer_id}"
      else
        "https://dashboard.stripe.com/test/customers/#{stripe_customer_id}"
      end
    end

    sig do
      params(
        filter: T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)],
        flag: T.any(String, Symbol)
      ).returns(T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)])
    end
    def sponsors_member_flag_filter(filter:, flag:)
      current_flags = T.let(Array.wrap(filter.fetch(:flags, [])), T::Array[String])
      flag_selected = current_flags.include?(flag)
      new_flags = flag_selected ? current_flags - [flag] : current_flags + [flag]
      if !flag_selected && SponsorsListing::SPONSORABLE_TIME_ZONE_FLAGS.include?(flag.to_sym)
        # Only user sponsorables have a time zone, so exclude org sponsorables because no 'T' flag will be visible
        # on their listing rows when filtering by a time zone-specific flag:
        filter.merge(flags: new_flags, type: "user")
      else
        filter.merge(flags: new_flags)
      end
    end

    sig do
      params(
        filter_key: T.any(String, Symbol),
        query: T.nilable(String),
        order: T.nilable(String),
        filter: T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)]
      ).returns(String)
    end
    def sponsors_member_clear_filter_path(filter_key, query:, order:, filter:)
      stafftools_sponsors_members_path(
        query: query,
        order: order,
        filter: opposite_sponsors_member_filter(filter_key, filter: filter),
      )
    end

    sig do
      params(
        filter_key: T.any(String, Symbol),
        filter: T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)]
      ).returns(T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)])
    end
    def opposite_sponsors_member_filter(filter_key, filter:)
      filter_value = filter[filter_key]
      case filter_key.to_sym
      when :ignored, :spammy, :suspended
        if filter_value.to_s == "all"
          # return to the default of showing only unignored/non-spammy/non-suspended listings
          filter.merge(filter_key => "0")
        else
          # clear the default filter, show all listings whether ignored/spammy/suspended or not
          filter.merge(filter_key => "all")
        end
      when :state
        if filter_value.to_s == "all"
          # return to the default of showing only Pending Approval listings
          filter.merge(filter_key => "pending_approval")
        else
          # clear the filter showing listings in a particular state to show those in any state
          filter.merge(filter_key => "all")
        end
      else
        filter.except(filter_key)
      end
    end

    sig do
      params(
        link_text: String,
        query: T.nilable(String),
        filter: T.any(String, T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)]),
        order: T.nilable(String),
        asc_order: T.nilable(String),
        desc_order: T.nilable(String)
      ).returns(String)
    end
    def sort_sponsors_listings_link(link_text, query:, filter:, order:, asc_order:, desc_order:)
      new_order = order == desc_order ? asc_order : desc_order
      query_params = { query: query, filter: filter, order: new_order }.to_query
      direction_icon = if order == asc_order
        :"triangle-up"
      elsif order == desc_order
        :"triangle-down"
      end
      direction_indicator = primer_octicon(direction_icon) if direction_icon
      link_to("?#{query_params}", class: "Link--primary") do
        safe_join([link_text, direction_indicator], " ")
      end
    end

    sig { params(created_at: T.nilable(ActiveSupport::TimeWithZone)).returns(String) }
    def account_age_description(created_at)
      return "--" unless created_at
      duration = ActiveSupport::Duration.build(Time.now - created_at).parts
      unit_mapping = { years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "min", seconds: "s" }
      unit_mapping.each do |time_unit, abbreviation|
        if time_amount = duration[time_unit]
          return "#{time_amount.round}#{abbreviation}"
        end
      end
      created_at.to_s
    end

    sig { params(listing: SponsorsListing).returns(String) }
    def sponsors_member_unsupported_time_zone_message(listing)
      messages = ["Time zone (#{listing.sponsorable_time_zone_name}) is not in a supported country"]
      unless listing.sponsorable_timezone_matches_country_of_residence?
        messages << "does not match country of residence"
      end
      messages.join(", ")
    end

    sig { params(created_at: T.any(DateTime, ActiveSupport::TimeWithZone)).returns(String) }
    def account_age_text_class(created_at)
      month_colors = { "danger" => 1, "severe" => 3, "attention" => 6, "default" => 12 }
      month_colors.each do |color, number|
        return "color-fg-#{color}" if created_at >= number.months.ago.beginning_of_month
      end
      "color-fg-muted"
    end

    sig { params(filter: T::Hash[T.any(Symbol, String), T.any(T::Array[String], String)]).returns(T::Boolean) }
    def show_bulk_approval_button?(filter)
      return true if filter[:state].blank?

      state_filter = filter[:state].to_s.downcase
      return true if state_filter == "pending_approval"
      return true if state_filter.starts_with?("not_") && state_filter != "not_pending_approval"

      false
    end

    sig { params(state: T.any(String, Symbol), current_order: T.nilable(String)).returns(T.nilable(String)) }
    def default_order_for_sponsors_listing_state(state, current_order)
      case state.to_s
      when "pending_approval"
        nil
      else
        current_order
      end
    end

    sig { params(check_met: T.nilable(T::Boolean), kwargs: T.untyped).returns(String) }
    def health_check_icon(check_met, **kwargs)
      icon_args = kwargs.merge(size: :small)

      if check_met
        icon_args.merge!(icon: :check, color: :success)
      else
        icon_args.merge!(icon: :alert, color: :danger)
      end

      primer_octicon(**icon_args)
    end

    sig { params(flags: T::Array[String]).returns(String) }
    def applied_stafftools_sponsors_listing_filters(flags)
      flags.map { |f| "#{f.titleize} (#{SponsorsListing::SPONSORABLE_FLAG_FILTERS[f.to_sym]})" }.join(", ")
    end
  end
end
