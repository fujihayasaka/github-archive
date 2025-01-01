# typed: true
# frozen_string_literal: true

module Api::App::ErrorDependency
  extend T::Helpers

  requires_ancestor { Api::App }

  ERROR_MAP = {
    "has already been taken" => "already_exists",
    "is invalid" => "invalid",
    "can't be blank" => "missing_field",
    GitHub::RateLimitedCreation::ERROR_MESSAGE => "abuse",
  }
  ERRORS = Set.new ERROR_MAP.values + %w(missing not_available too_large unauthorized unprocessable)

  ERROR_MESSAGE_RATE_LIMIT = "You have exceeded a secondary rate limit and have been temporarily blocked from content creation. Please retry your request again later."
  DOC_URL_RATE_LIMIT = "/rest/overview/rate-limits-for-the-rest-api#about-secondary-rate-limits"

  # Public: Creates an Error object for being serialized to JSON.
  #
  # resource - The String resource name (usually the AR model name)
  # field    - The String field name that the error is for.
  # code     - The String error code.  Possible values should be documented.
  # options  - Optional Hash of more error properties to add.
  #
  # Returns a Hash
  if Rails.env.test?
    # blow up early in tests
    def api_error(resource, field, code, options = {})
      raise "Invalid Error: #{code.inspect}" unless ERRORS.include?(code.to_s)
      options.update resource: resource, field: field, code: code
    end
  else
    def api_error(resource, field, code, options = {})
      options.update resource: resource, field: field, code: code
    end
  end

  # Public: Delivers an error response for this request.
  #
  # status  - Integer HTTP status code of the error.
  # options - Optional Hash to customize the error output.  Extra options are
  #           passed through to #deliver.
  #           :message           - String describing the error.
  #           :documentation_url - String URL for the documentation that will
  #                                help the user understand and resolve the
  #                                error (optional)
  #                                (default: 'https://developer.github.com').
  #           :errors            - Array of Strings with more detailed errors.
  #           :resource          - Optional String to override automatically-
  #                                detected resource.
  #
  # Returns a String body to be used as the response of this request.
  def deliver_error(status, options = {})
    doc_url = options.delete(:documentation_url)
    data = {}
    data[:message] = options.delete(:message)

    if err = options.delete(:errors)
      # Content creation rate limits are done as validations, so they'll get
      # here as a 422 (which is correct for browser flow). But they represent a
      # rate limit, so fix it to a more appropriate 403 for for API responses.
      if err.respond_to?(:full_messages)
        if err[:base].any? { |message| message.include?(GitHub::RateLimitedCreation::ERROR_MESSAGE) }
          status = 403
          data = parse_rate_limit_error(data, err)
        else
          data[:errors] = convert_error(err, options[:resource])
        end
      else
        data[:errors] = err
      end
    end

    if OpenApi::IGNORE_REASONS.include?(@documentation_url)
      doc_url ||= default_documentation_url
    else
      doc_url ||= @documentation_url || default_documentation_url
      doc_url = GitHub.developer_help_url + doc_url unless doc_url =~ /^http/
    end

    data[:documentation_url] ||= doc_url

    data[:message] ||=
      case status
      when 404 then "Not Found"
      when 400 then "Bad Request"
      when 401 then "Requires authentication"
      when 403 then "Rate Limit Exceeded"
      when 409 then "Conflict"
      when 415 then "Unsupported Media Type"
      when 422 then "Validation Failed"
      when 301 then "Moved Permanently"
      when 302 then "Found"
      else          "Server Error"
      end

    # adding a status expressed as a json string to the response
    data[:status] = status.to_s

    deliver_raw data, options.update(status: status)
  end

  def parse_rate_limit_error(data = {}, err = nil, klass: nil)
    doc_url = DOC_URL_RATE_LIMIT

    root_error_message = if root_of_error = err&.instance_variable_get(:@base)
      root_of_error.class.to_s.underscore
    elsif klass
      klass.to_s.underscore
    else
      nil
    end
    log_rate_limited_request(detailed_message: root_error_message)
    data[:message] = ERROR_MESSAGE_RATE_LIMIT
    data[:message] += Api::ErrorHelper.rate_limit_message_for_request_id(GitHub.context[:request_id])
    data[:documentation_url] = doc_url
    data
  end

  def convert_error(errors, resource = nil)
    Api::Serializer.validation_errors(errors, resource)
  end

  # Halts the request with an error.
  #
  # status  - Integer HTTP status code of the error.
  # options - Optional Hash to customize the error output.
  #           :message - String describing the error.
  #           :errors  - Array of Strings with more detailed errors.
  #
  # Halts with the given status and String response.
  # Returns nothing.
  sig { params(status: Integer, options: T.any(T::Hash[Symbol, T.untyped], GitHub::Options)).returns(T.noreturn) }
  def deliver_error!(status, options = {})
    halt deliver_error(status, options)
  end

  def deliver_pagination_cap_exceeded!
    controller = GitHub::TaggingHelper.controller(env)
    action = GitHub::TaggingHelper.action(env)
    method = GitHub::TaggingHelper.request_method(env)

    tags = []
    tags << "via:api"
    tags << "controller:#{controller}" if controller
    tags << "action:#{action}" if action
    tags << "method:#{method}" if method

    GitHub.dogstats.increment("pagination_cap", tags: tags)

    message =  "In order to keep the API fast for everyone, pagination is limited "\
               "for this resource."

    deliver_error! 422,
      message: message,
      documentation_url: "/v3/#pagination"
  end

  def default_documentation_url
    GitHub.developer_help_url + "/rest"
  end

  def deliver_schema_validation_error!(result, documentation_url: nil)
    error_messages = result.error_messages.join("\n")
    options = { message: "Invalid request.\n\n#{error_messages}" }
    options[:documentation_url] = documentation_url if documentation_url.present?

    deliver_error! 422, options
  end

  # Private: Convert an array of string based path elements to integers if they
  # exist.
  #
  # path - An array of strings.
  #
  # Examples
  #
  # path = ["input", "labelNames", "1"]
  # path_with_integer_based_index(path)
  # #=> ["input", "labelNames", 1]
  #
  # Returns an array of strings and integers.
  def path_with_integer_based_index(path)
    return unless path

    path.map do |element|
      if element =~ /\A\d+\z/
        element.to_i
      else
        element
      end
    end
  end

  # Write to logs & Hydro context that a rate limiter was applied.
  # @return void
  def log_rate_limited_request(detailed_message: nil)
    logging_limit_message ||= "api/rate-limited-creation"

    if detailed_message
      logging_limit_message += "/#{detailed_message}"
    end

    if (log_data = env[Rack::RequestLogger::APPLICATION_LOG_DATA])
      log_data["gh.rate_limit.secondary.limit_reason"] = logging_limit_message
    end

    if (hydro_payload = env[GitHub::HydroMiddleware::PAYLOAD])
      hydro_payload["secondary_rate_limit_reason"] = logging_limit_message
    end
  end
end
