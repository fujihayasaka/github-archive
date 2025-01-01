# typed: true
# frozen_string_literal: true

module ApplicationController::AnalyticsDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    unless GitHub.enterprise?
      before_action :store_utm_parameters
    end
    helper_method :analytics_ec_meta_tags
    helper_method :analytics_event_meta_tags
    helper_method :controller_action_slug
    helper_method :referral_labels
  end

  # Publishes an analytics event in Hydro.
  #
  # Structure is mapped heavily off of Google Analytics Event API:
  # https://developers.google.com/analytics/devguides/collection/gajs/eventTrackerGuide
  #
  # event - Hash describing the event.
  #   :category - String describing the category of event. Required.
  #   :action   - String describing what happened. Required.
  #   :label    - String labeling the event. Title of the content, etc.
  #
  # Returns nothing.
  def analytics_event(category:, action:, label: nil)
    return if GitHub.enterprise?

    event_params = {
      actor: current_user,
      category: category,
      action: action,
      label: stringify_ga_label(label),
    }

    GlobalInstrumenter.instrument("analytics.event", event_params)
  end

  PLAN_TO_PRODUCT = {
    "pro" => { name: "Developer", position: 1 },
    "business" => { name: "Team", position: 2 },
    "business_plus" => { name: "Business", position: 3 },

  }

  # Track a Google Analytics ecommerce purchase event
  #
  # target - User object on whom we're tracking the purchase event.
  # revenue - Numeric revenue in dollars.
  # context - String description context. e.g. "Signup", "Upgrade"
  #
  # Returns nothing.
  def analytics_ec_purchase(target, revenue, context)
    product = PLAN_TO_PRODUCT[target.plan.name]
    id = "#{target.id}-#{Time.now.to_i}"
    revenue = Billing::Money.new(revenue * 100) unless revenue.is_a?(Money)

    if product && revenue > 0
      flash[:analytics_ec_payload] = [
        ["ec:addProduct", product],
        ["ec:setAction", "purchase", {
          "id" => id,
          "revenue" => revenue.format(symbol: false),
          "list" => context,
        }],
      ]
    end
  end

  def set_analytics_dimension(name:, value:, redirect: false)
    dimension = { "name" => name, "value" => value }

    if redirect
      flash[:analytics_dimension] = dimension
    else
      flash.now[:analytics_dimension] = dimension
    end
  end

  # Set a flash which would later on be used in view-side JavaScript to
  # override the URL we send to Google Analytics. Common uses including
  # masking private data and preventing high-cardinality dimensions.
  #
  # url - String of modified URL.
  #
  # Returns nothing.
  def override_analytics_location(url)
    flash.now[:analytics_location] = url
  end

  # Stores UTM parameters in the session.
  #
  # This is useful for forwarding `utm_*` parameters to external links such as
  # enterprise.github.com (using enterprise_web_url).
  def store_utm_parameters
    # Skip if action disables sessions
    return unless request.get? && session

    get_params = request.GET
    utm_keys = get_params.keys.grep(/\Autm_/)
    return unless utm_keys.any?

    session[:utm_memo] = utm_keys.each_with_object({}) do |key, memo|
      memo[key] = get_params[key]
    end
  end

  # Tell JavaScript to strip any parameters from the URL we report to Google
  # Analytics.
  #
  # Returns nothing.
  def strip_analytics_query_string
    flash.now[:analytics_location_query_strip] = "true"
  end

  private

  # Stringify hash object into key/value pairs for event labels. Turns
  # `{:target => "User", :billing => false}` into `target:User; billing:false`.
  #
  # Returns a String.
  def stringify_ga_label(label_content)
    return label_content.presence unless label_content.is_a?(Hash)
    label_content.map { |key, value| "#{key}:#{value}" }.join("; ")
  end

  # Since we embrace CSP, we need a way to trigger javascript calls without
  # javascript. Weird. So we spit out analytics events as meta tags and
  # rely on google-analytics.coffee to send them to Google.
  #
  # Returns an HTML String.
  def analytics_event_meta_tags
    return unless flash[:analytics_events].respond_to?(:map)

    tags = flash[:analytics_events].map do |event|
      event_params = [event["category"], event["action"], event["label"]]
      event_params << event["value"] if event["value"].present?

      tag(:meta,
        :name => "analytics-event",
        :content => event_params.join(", "),
        "data-turbo-transient" => true,
      )
    end

    safe_join(tags)
  end

  def analytics_ec_meta_tags
    if payload = flash[:analytics_ec_payload]
      tag(:meta,
        :name => "analytics-ec-payload",
        :content => JSON.dump(payload),
        "data-turbo-transient" => true,
      )
    end
  end

  # Returns the current controller and action. Example: files#disambiguate
  def controller_action_slug
    [params[:controller], params[:action]].join "#"
  end

  def referral_labels(labels)
    labels += "ref_page:#{params[:ref_page]};" if params[:ref_page]
    labels += "ref_cta:#{params[:ref_cta]};" if params[:ref_cta]
    labels += "ref_loc:#{params[:ref_loc]};" if params[:ref_loc]
    labels
  end
end
