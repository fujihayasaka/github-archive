# typed: true
# frozen_string_literal: true

module Api::App::ShortcodeDetectionHelper
  extend T::Helpers
  extend T::Sig
  requires_ancestor { Api::App }

  # Inspect each param in the payload body.
  # Return true and log a violation if the payload contains a shortcode.
  # Return false if there are no shortcodes in the payload.
  # This detection only expects the payload to contain certain types, so if we see an unexpected type we also log.
  def block_suffixed_params?(object, business:, namespace:, blocking_enabled:)
    return false unless business&.shortcode
    return false unless GitHub.multi_tenant_enterprise?
    return false if business&.stafftools_tenant?
    # internal api calls are exempt
    return false if GitHub::Routers::Api.internal_api_host?(request.host)
    return false unless object.present?

    unless should_inspect?(object, business: business) || object.is_a?(String)

      log_api_param_type(object.class.name, business: business, namespace: namespace)
      return false
    end

    shortcode = business.shortcode
    suffix_include = "_#{shortcode}"

    queue = T.let([object], T::Array[T.untyped])
    until queue.empty?
      current = queue.shift
      if should_inspect?(current, business: business)
        values = get_values_from_collection(current, business: business, namespace: namespace)
        next unless values.present?

        values.each do |value|
          queue << value
        end
      elsif current.is_a?(String) && current.include?(suffix_include)
        log_api_suffix_blocked(current, business: business, namespace: namespace, blocking_enabled: blocking_enabled)
        return true
      elsif should_log_unexpected_type?(current, business: business)
        log_api_param_type(current.class.name, business: business, namespace: namespace)
      end
    end

    false
  end

  def get_values_from_collection(collection, business:, namespace:)
    if collection.is_a?(Hash)
      collection.values
    elsif collection.is_a?(Google::Protobuf::RepeatedField)
      collection.to_a
    elsif collection.is_a?(Platform::GraphqlResponse)
      if self.respond_to?(:encode_json)
        [encode_json(collection)]
      else
        log_api_param_type(collection.class.name, business: business, namespace: namespace)
        nil
      end
    elsif collection.is_a?(Platform::ParseErrorResponse)
      # Platform::ParseErrorResponse#errors returns an array
      collection.errors
    else
      # Array
      collection
    end
  end

  def log_api_suffix_blocked(violation, business:, namespace:, blocking_enabled:)
    log_fields = {
      "code.namespace" => namespace,
      "code.function" => "log_api_suffix_blocked",
      "http.url" => request.url,
      "http.method" => request.request_method,
      "http.user_agent" => request.user_agent,
      "gh.business.id" => business.id,
      "gh.business.shortcode" => business.shortcode,
      "gh.external_identities.payload_violation" => violation,
      "gh.blocking_enabled" => blocking_enabled,
    }

    if request.referrer
      log_fields.merge!({ "http.request.header.referer" => request.referrer })
    end

    GitHub.logger.error(log_fields)
  end

  def log_api_param_type(class_name, business:, namespace:)
    log_fields = {
      "code.namespace" => namespace,
      "code.function" => "log_api_param_type",
      "gh.external_identities.payload_type" => class_name,
      "http.url" => request.url,
      "http.method" => request.request_method,
      "http.user_agent" => request.user_agent,
      "gh.business.id" => business.id,
      "gh.business.shortcode" => business.shortcode,
    }

    if request.referrer
      log_fields.merge!({ "http.request.header.referer" => request.referrer })
    end

    GitHub.logger.info(log_fields)
  end

  # Is the passed object a known collection type that we should inspect?
  sig { params(object: T.untyped, business: Business).returns(T::Boolean) }
  def should_inspect?(object, business:)
    return true if object.is_a?(Hash)
    return true if object.is_a?(Array)
    return true if object.is_a?(Google::Protobuf::RepeatedField)
    return true if object.is_a?(Platform::GraphqlResponse)
    return true if object.is_a?(Platform::ParseErrorResponse)

    false
  end

  # Is the passed object a type that should be logged as an unexpected type?
  sig { params(object: T.untyped, business: Business).returns(T::Boolean) }
  def should_log_unexpected_type?(object, business:)
    return false if [String, NilClass, TrueClass, FalseClass, Symbol].include?(object.class)
    return false if object.is_a?(Numeric)
    return false if object.is_a?(ActiveSupport::TimeWithZone)
    return false if object.is_a?(Date)
    return false if object.is_a?(GraphQL::Client::Schema::EnumType::EnumValue)
    return false if object.is_a?(ActiveSupport::SafeBuffer)

    true
  end
end
