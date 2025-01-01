# typed: false
# frozen_string_literal: true

module HydroHelper
  extend self
  include EscapeHelper

  InvalidPayloadError = Class.new(ArgumentError)
  HYDRO_CLIENT_CONTEXT_PERMITTED_KEYS = %w[
    title_length
    number_of_similar_issues
    position_in_list
    title_string_at_time_of_click
    id_of_clicked_result
    results_shown_at_time_of_click
    starting_diff_position
    ending_diff_position
    line_count
    octolytics_id
    feature_flag_enabled
    file_filter_checked
    tree_file_count
    query
    processor_response_code
    processor_response_reason
  ]

  # Given an event type and payload, produce data attributes for use in a view.
  # If the payload HMAC cannot be computed (e.g., because the secret is not set
  # or the data is nil) an empty Hash is returned. This is done instead of
  # returning nil so you can merge in other data attributes you may be using.
  #
  # event_type - a String naming the hydro instrumentation that will listen for this event
  # payload    - a Hash of event data
  #
  # Returns a (potentially empty) Hash of attributes to be used with the Rails data parameter.
  def hydro_click_tracking_attributes(event_type, payload)
    payload = encode_hydro_payload(event_type, payload)
    hmac = hydro_payload_hmac(payload)

    return {} unless hmac

    # NOTE: These become the data-hydro-click and data-hydro-click-hmac attributes in the HTML
    { "hydro-click" => payload, "hydro-click-hmac" => hmac }
  end

  # To be used with logged out JS implementation of feature flags at feature.ts
  # Instruments feature flag enabled/disabled for visitors to use in data analysis
  def hydro_feature_flag(feature:)
    payload = encode_hydro_payload("feature_flag_decision", { feature: feature })
    hmac = hydro_payload_hmac(payload)
    return {} unless hmac

    safe_data_attributes({
      "feature-hydro" => payload,
      "feature-hydro-hmac" => hmac
    })
  end

  # Given an event type and payload, produce data attributes for use in a view.
  # If the payload HMAC cannot be computed (e.g., because the secret is not set
  # or the data is nil) an empty Hash is returned. This is done instead of
  # returning nil so you can merge in other data attributes you may be using.
  #
  # event_type - a String naming the hydro instrumentation that will listen for this event
  # payload    - a Hash of event data
  #
  # Returns a (potentially empty) Hash of attributes to be used with the Rails data parameter.
  def hydro_view_tracking_attributes(event_type, payload)
    payload = encode_hydro_payload(event_type, payload)
    hmac = hydro_payload_hmac(payload)

    return {} unless hmac

    # NOTE: These become the data-hydro-view and data-hydro-view-hmac attributes in the HTML
    { "hydro-view" => payload, "hydro-view-hmac" => hmac }
  end

  def encode_hydro_payload(event_type, payload)
    payload = payload.merge(originating_url: GitHub.context[:url])
    payload[:user_id] ||= GitHub.context[:actor_id]
    GitHub::JSON.encode(event_type: event_type, payload: payload)
  end

  def decode_hydro_payload(encoded:, hmac:)
    unless SecurityUtils.secure_compare(hmac, hydro_payload_hmac(encoded))
      raise InvalidPayloadError.new("Invalid HMAC")
    end

    begin
      decoded = GitHub::JSON.decode(encoded)
    rescue Yajl::ParseError
      raise InvalidPayloadError.new("Invalid JSON")
    end

    unless decoded.is_a?(Hash)
      raise InvalidPayloadError.new("Expected a Hash, got #{decoded.class}")
    end

    decoded.with_indifferent_access
  end

  # Calculate the HMAC for data using GitHub.hydro_browser_payload_secret. If
  # data is nil or GitHub.hydro_browser_payload_secret is not set, returns nil.
  #
  # data - a String (presumably of JSON) to be authenticated
  #
  # Returns the HMAC as a hex string or nil.
  def hydro_payload_hmac(data)
    unless data.nil? || GitHub.hydro_browser_payload_secret.nil?
      OpenSSL::HMAC.hexdigest("sha256", GitHub.hydro_browser_payload_secret, data)
    end
  end

  # Takes a JSON string, parses it and removes any keys that
  # are not permitted (HYDRO_CLIENT_CONTEXT_PERMITTED_KEYS.)
  #
  # client_context_string - a String (presumably of JSON)
  #
  # Returns Hash
  def decode_hydro_client_context(client_context_string)
    return {} if client_context_string.blank?

    begin
      client_context = GitHub::JSON.decode(client_context_string)
    rescue Yajl::ParseError
      return {}
    end

    return {} unless client_context.is_a?(Hash)

    client_context.slice(*HYDRO_CLIENT_CONTEXT_PERMITTED_KEYS).with_indifferent_access
  end

  # (Deprecated) Generate analytics tags from content, with the format:
  # {
  #   category: "Hero", (defaults to same value as "text")
  #   action: "click to Sign up",
  #   label: "ref_cta:Sign up;"
  # }
  # Used to enable analytics for marketing CTAs rendered
  # through components, even when no analytics is set up.
  # Note that analytics data that is explicitly passed
  # is not overriden - it's only padded
  def analytics_tags_from_content(analytics: {}, text:)
    analytics = analytics.present? ? analytics : {} # if nil is passed to this method, overriding the default value
    # Defaults - only used if nothing is explicitly passed
    category = text
    action = "click to #{text}"
    label = "ref_cta:#{text};"
    label = "#{label}ref_loc:#{analytics[:ref_loc]};" if analytics[:ref_loc].present?
    label = "#{label}ref_loc:#{analytics[:location_in_page]};" if analytics[:location_in_page].present?

    analytics[:category] = analytics[:category].present? ? analytics[:category] : category
    analytics[:action] = analytics[:action].present? ? analytics[:action] : action
    analytics[:label] = analytics[:label].present? ? analytics[:label] : label
    analytics.delete(:ref_loc) if analytics[:ref_loc].present?

    analytics
  end

  # This version of the method uses the latest schema for marketing pages
  # Generate analytics tags from content, with the format:
  # {
  #    context: "enterprise_subnav",
  #    location: "navbar",
  #    tag: "link"
  # }
  # Used to enable analytics for marketing CTAs through components
  def analytics_tags_from_content_v2(analytics: {}, text:)
    analytics = analytics.present? ? analytics : {} # if nil is passed to this method, overriding the default value
    # Defaults - only used if nothing is explicitly passed
    action = text.parameterize.underscore.downcase
    tag = "unknown"
    location = "unknown"
    analytics[:action] = analytics[:action].present? ? analytics[:action] : action
    analytics[:context] = analytics[:context].present? ? analytics[:context].downcase : text.downcase
    analytics[:tag] = analytics[:tag].present? ? analytics[:tag] : tag
    analytics[:location] = analytics[:location].present? ? analytics[:location] : location

    analytics
  end
end
