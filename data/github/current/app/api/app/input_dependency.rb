# typed: true
# frozen_string_literal: true

# Functionality related to receiving request input (e.g., unpacking it, parsing
# parsing it, validating that it satisfies a schema).

module Api::App::InputDependency
  include Api::App::ShortcodeDetectionHelper
  # Public: Receive JSON from the request body and parse it.
  #
  # expected_type  - An optional Class that is used to check the basic type of
  #                 the parsed JSON object.  Usually `Hash` or `Array`.
  # required       - Optional Boolean that determines if the type or JSON is
  #                 required.  Default: true if the expected type is set.
  # check_encoding - Optional boolean to determine whether or not to attempt to decode the request body
  #                  This is currently added as an option due to the feature-flag check relying on `current_user`,
  #                  and Api::Lfs inspects the request body in `attempt_login`, but this can be removed once we
  #                  have fully shipped this feature-flagged code. Defaults to `true` if omitted.
  #
  # Halts with a 400 if the JSON is invalid.
  # Returns the parsed JSON Object.
  def receive(expected_type = nil, required: true, check_encoding: true)
    json = if check_encoding && FeatureFlag.vexi.enabled?(:api_add_support_for_content_encoded_request_body, current_user, default: false)
      encoding = request.env["HTTP_CONTENT_ENCODING"]

      GitHub.tracer.in_span("Api::App::InputDependency#receive_encoding", kind: :internal, attributes: { "http.request.content_encoding" => encoding || "nil" }) do
        if encoding.nil?
          request.body.read
        elsif encoding.casecmp?("gzip")
          Zlib::GzipReader.new(request.body).read
        else
          GitHub.logger.info(
            "Unable to decode content from request due to unexpected encoding",
            "code.namespace": "Api::App::InputDependency",
            "code.function": "receive",
            "http.request.header.content_encoding": encoding,
            "gh.request_id": request_id
          )
          halt 415
        end
      end
    else
      request.body.read
    end

    receive_json(json, type: expected_type, required: required)
  end

  # Public: Receive JSON from the request body and parse it.
  #
  # expected_type  - An optional Class that is used to check the basic type of
  #                 the parsed JSON object.  Usually `Hash` or `Array`.
  # required       - Optional Boolean that determines if the type or JSON is
  #                 required.  Default: true if the expected type is set.
  # check_encoding - Optional boolean to determine whether or not to attempt to decode the request body
  #                  This is currently added as an option due to the feature-flag check relying on `current_user`,
  #                  and Api::Lfs inspects the request body in `attempt_login`, but this can be removed once we
  #                  have fully shipped this feature-flagged code. Defaults to `true` if omitted.
  # max_byte_size  - Optional Integer maximum allowed byte size of the request body.
  #                  When set, halts with a 415 if the body exceeds this size.
  #                  Default: nil (no limit).
  # max_depth      - Optional Integer maximum allowed nesting depth of the JSON body.
  #                  When set, halts with a 415 if nesting exceeds this depth.
  #                  Uses a fast pre-scan heuristic on the raw string.
  #                  Default: nil (no limit).
  #
  # Halts with a 400 if the JSON is invalid.
  # Halts with a 415 if the body exceeds max_byte_size or max_depth.
  # Returns the parsed JSON Object.
  def receive_with_limits(expected_type = nil, required: true, check_encoding: true, max_byte_size: nil, max_depth: nil)
    json = if check_encoding && FeatureFlag.vexi.enabled?(:api_add_support_for_content_encoded_request_body, current_user, default: false)
      encoding = request.env["HTTP_CONTENT_ENCODING"]

      GitHub.tracer.in_span("Api::App::InputDependency#receive_encoding", kind: :internal, attributes: { "http.request.content_encoding" => encoding || "nil" }) do
        if encoding.nil?
          read_body_with_limit(request.body, max_byte_size)
        elsif encoding.casecmp?("gzip")
          read_gzip_with_limit(request.body, max_byte_size)
        else
          GitHub.logger.info(
            "Unable to decode content from request due to unexpected encoding",
            "code.namespace": "Api::App::InputDependency",
            "code.function": "receive",
            "http.request.header.content_encoding": encoding,
            "gh.request_id": request_id
          )
          halt 415
        end
      end
    else
      read_body_with_limit(request.body, max_byte_size)
    end

    if max_depth && json_exceeds_depth?(json, max_depth)
      GitHub.dogstats.increment("api.input_dependency.receive.max_depth_exceeded", tags: [])
      halt 415
    end

    receive_json(json, type: expected_type, required: required)
  end

  # Internal: Read from an IO, enforcing an optional byte-size cap during the
  # read so that an oversized payload is rejected without buffering it entirely.
  #
  # io            - An IO-like object that responds to #read.
  # max_byte_size - Optional Integer cap. nil means unlimited.
  #
  # Returns the String body.
  # Halts with 415 if the body exceeds max_byte_size.
  def read_body_with_limit(io, max_byte_size)
    if max_byte_size
      data = io.read(max_byte_size + 1)
      if data && data.bytesize > max_byte_size
        GitHub.dogstats.increment("api.input_dependency.receive.max_byte_size_exceeded", tags: [])
        halt 415
      end
      data || "".b
    else
      io.read
    end
  end

  # Internal: Decompress a gzip-encoded IO, enforcing an optional byte-size cap
  # during decompression so that a decompression bomb is rejected without
  # expanding the full payload into memory.
  #
  # io            - An IO-like object containing gzip-compressed data.
  # max_byte_size - Optional Integer cap on decompressed size. nil means unlimited.
  #
  # Returns the decompressed String body.
  # Halts with 415 if the decompressed body exceeds max_byte_size.
  def read_gzip_with_limit(io, max_byte_size)
    gz = Zlib::GzipReader.new(io)

    if max_byte_size
      # Read up to max_byte_size + 1 so we can detect overflow without
      # decompressing the entire stream.
      data = gz.read(max_byte_size + 1)
      if data && data.bytesize > max_byte_size
        GitHub.dogstats.increment("api.input_dependency.receive.max_byte_size_exceeded", tags: [])
        halt 415
      end
      data || "".b
    else
      gz.read
    end
  end

  # Public: Converts a message from the API that talks about Ruby objects to talk
  # about JavaScript objects.
  #
  # message - A string whose references to Ruby objects should change
  #
  # Returns a string
  def translate_ruby_type_name_to_json_type_name(string)
    string.sub(/Hash/i, "object")
  end

  # Public: Parse the given JSON.
  #
  # type     - An optional Class that is used to check the basic type of the
  #            parsed JSON object.  Usually `Hash` or `Array`.
  # required - Optional Boolean that determines if the type or JSON is required.
  #            Default: true if the expected type is set.
  #
  # Halts with a 400 if the JSON is invalid.
  # Returns the parsed JSON Object.
  def receive_json(json, type: nil, required: true)
    required = false unless type

    res = GitHub::JSON.parse(json) unless json.blank?
    check_type = type && (required || res)

    if check_type && !res.is_a?(type)
      deliver_error! 400, message: "Body should be a JSON #{translate_ruby_type_name_to_json_type_name(type.to_s)}"
    end

    business = GitHub::CurrentTenant.get
    if business && block_suffixed_params?(res, business: business, namespace: "Api::App::InputDependency", blocking_enabled: true)
      deliver_error! 404, message: "Unable to complete request that contains suffixed values in the request parameters. Remove the suffix and request again."
    end

    res
  rescue Yajl::ParseError, StandardError # rubocop:todo Lint/RescueException
    deliver_error! 400, message: "Problems parsing JSON"
  end

  # Public: Receive JSON from the client, parse it, and validate that it
  # satisfies the schema for requests that perform the specified action on the
  # specified type of resource.
  #
  # resource          - The String name of the type of resource that the request is
  #                     operating on.
  # rel               - The String name of the rel that uniquely identifies the type of
  #                     action that the request is performing on the resource.
  # skip_validation   - The Boolean that identifies whether to skip validating
  #                     the JSON schema
  # expected_type     - An optional Class that is used to check the basic type of
  #                     the parsed JSON object.  Usually `Hash` or `Array`.
  #                     Should be nil unless skip_validation is true
  # documentation_url - Optional string for the documentation url to include in the
  #                     response if there is a schema error.
  # required          - Optional Boolean that determines if the type or JSON is
  #                     required.  Default: true if the expected type is set.
  #
  # Examples
  #
  #   receive_with_schema("label", "update")
  #
  #   receive_with_schema("label", "update", skip_validation: true)
  #
  # Halts with a 422 if the JSON is invalid and skip_validation is false.
  # Returns a Hash or an Array (depending on the format of the request data).
  def receive_with_schema(resource, rel, skip_validation: false, expected_type: nil,  documentation_url: nil, required: true)
    # Be Kind, Please Rewind
    # This ensures that if we have already read the request
    # body we can read it again.
    request.body.rewind

    data = receive(expected_type, required: required)

    unless skip_validation
      result = validate_with_schema(data: data, resource: resource, request: request)
      unless result.valid?
        if documentation_url.present?
          deliver_schema_validation_error!(result, documentation_url: documentation_url)
        else
          deliver_schema_validation_error!(result)
        end
      end
    end

    if data && (data.is_a?(Hash) || data.is_a?(Array))
      data
    else
      {}
    end
  end

  def validate_with_schema(data:, resource:, request:)
    Api::V3SchemaCollection.validate(data: data, resource: resource, route: request.env["sinatra.route"])
  end

  # Public: Verify that the given data satisfies the schema for requests that
  # perform the specified action on the specified type of resource.
  #
  # data     - The Hash or Array representing the request input.
  # resource - The String name of the type of resource that the request is
  #            operating on.
  # rel      - The String name of the rel that uniquely identifies the type of
  #            action that the request is performing on the resource.
  #
  # Halts with a 422 if the data violates the schema.
  # Returns nothing.
  def ensure_data_satisfies_schema!(data, resource, rel)
    result = Api::V3SchemaCollection.validate(data: data, resource: resource, rel: rel)

    return if result.valid?

    deliver_schema_validation_error!(result)
  end

  # @return [OpenApi::Validation::ValidationResult]
  def validate_with_openapi(data:, operation:, request:)
    timer = Timer.start

    if @selected_api_version
      operation = OpenApi::Description::VersionedOperation.new(
        operation.raw,
        @selected_api_version.version,
      )
    end

    request_validation_settings = OpenApi::Validation::RequestValidationSettings.new(
      validate_path_parameters: false,
      validate_extra_query_parameters: false,
      allow_skipping_validation: true
    )

    validator = OpenApi::Validation::RequestValidator.new(
      operation: operation,
      validation_settings: request_validation_settings
    )

    result = validator.validate(request, [])

    timer.stop
    GitHub.dogstats.distribution("openapi.validation.request", timer.elapsed_ms, tags: ["operation_id:#{operation&.id}"])

    result
  end

  def deliver_openapi_validation_error!(result)
    error_messages = result.errors.map(&:public_error).join("\n")
    deliver_error! 422, message: "Invalid request.\n\n#{error_messages}"
  end

  # Validates an incoming request against an OpenAPI operation
  #
  # @param operation [String] The OpenAPI operation to validate against
  # @param skip_validation [Boolean] Whether to validate requests in production or not
  # @return [Object] The validated input JSON
  def receive_with_openapi(skip_validation: false, expected_type: nil, required: true)
    if @operation.nil?
      raise "@operation needs to be set for OpenAPI request validation. Make sure you are using :operation_id when defining your endpoint."
    end

    request.body.rewind

    data = receive(expected_type, required: required)

    unless skip_validation
      result = validate_with_openapi(
        data: data,
        operation: @operation,
        request: request
      )

      deliver_openapi_validation_error!(result) if !result.valid?
    end

    if data && (data.is_a?(Hash) || data.is_a?(Array))
      data
    else
      {}
    end
  end

  # Public: Extracts the given keys from the data.  Think of this like
  # `attr_accessible`.  Attributes ending in `_at` or `_on` are parsed into
  # Time objects.
  #
  # data - A Hash of attributes to be set on an object.
  # keys - Array of Symbol keys.
  #
  # Returns a sanitized Hash.
  def attr(data, *keys)
    return nil if data.nil?
    options = keys.extract_options!
    prefix = options[:prefix]
    hash = {}

    return hash unless data.is_a?(Hash)

    keys.each do |k|
      k_s = k.to_s
      if data.has_key?(k_s)
        value = data[k_s]
        if k_s =~ /_(at|on)$/ && value
          value = Time.parse(value) unless value.respond_to?(:utc)
          value = value.localtime if value.utc?
        end
        k_s = "#{prefix}#{k_s}" if prefix
        hash[k_s] = value
      end
    end
    hash.with_indifferent_access
  end

  # Returns the given request parameter as an Integer, either
  # logging or halting if the supplied parameter value is not
  # the exact String representation of the Integer value.
  #
  # key  - Symbol request parameter key containing the id
  #        (default: :id)
  # halt - Boolean for whether to halt with an error or just log
  #        (default: false)
  #
  # returns the Integer value of the parameter, or halts with a 422
  def int_id_param!(key: :id, halt: false)
    id = params[key].try(:b)

    unless id =~ /\A\d+\z/

      if halt
        message = "The #{key} parameter must be an integer."
        deliver_error!(422, message: message)
      end
    end

    id.to_i
  end

  # Returns the request parameter as a Time, halting if
  # the supplied parameter value cannot be parsed as a Time value.
  def time_param!(key)
    return nil if params[key].blank?

    message = "The #{key} parameter needs to be in " \
              "ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ"

    parse_time!(params[key], message: message)
  end

  def parse_time!(value, options = {})
    begin
      time = Time.parse(value)
      if GitHub::Validations::DatetimeInSupportedRangeValidator.datetime_in_supported_range?(time)
        return time
      else
        options[:message] ||= "Time values must be in the range " \
                              "1000-01-01T00:00:00Z to 9999-12-31T23:59:59Z"
      end
    rescue StandardError # rubocop:todo Lint/RescueException
      options[:message] ||= "Time values must be in " \
                            "ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ"
    end

    options[:documentation_url] ||= @documentation_url || "/v3/#schema"
    deliver_error! 422, options
  end

  # Checks if a given request parameter contains a properly formatted
  # SHA string.
  #
  # key  - Symbol request parameter key containing the SHA
  # data - Hash of data to check for the key
  #        (optional, defaults to params hash)
  #
  # Returns a String or halts with 422
  def sha_param!(key, data = nil)
    message = "The #{key} parameter must be exactly 40 characters " \
              "and contain only [0-9a-f]."

    sha = (data || params)[key]
    deliver_error!(422, message: message) unless GitRPC::Util.valid_full_oid?(sha)

    sha
  end

  # Internal: Decodes URL-encoded push user data
  #
  # data   -  Hash with push data that should be URL decoded
  #
  # Modified passed data hash.
  def decode_push_data!(data)
    %w[pusher hook_warning hook_error real_ip committed_at].each do |name|
      data[name] = CGI.unescape(data[name]) if data[name]
    end

    begin
      data["committed_at"] = Time.parse(data["committed_at"]) if data["committed_at"].present?
    rescue ArgumentError, TypeError => err
      Failbot.report(err)
      data["committed_at"] = Time.current
    end

    data["ref_updates"].each do |ref_update|
      ref_update["refname"] = CGI.unescape(ref_update["refname"])
    end

    # "stat=push_option_0=foobar",
    # "stat=push_option_count=1"
    if data["sockstat"].respond_to?(:grep)
      push_options = data["sockstat"].grep(/\Astat=push_option_\d\d?=(.{1,1000})\z/) { |_| $1 }
      data["push_options"] = push_options if push_options.any?
    end
  end

  # Internal: Fast pre-scan heuristic to check whether a JSON string's nesting
  # depth exceeds a given limit. Scans for `{`, `}`, `[`, `]` while skipping
  # over string literals to avoid false positives from bracket characters
  # inside strings. Returns early as soon as the limit is exceeded.
  #
  # json      - The raw JSON String to scan.
  # max_depth - Integer maximum allowed nesting depth.
  #
  # Returns true if nesting exceeds max_depth, false otherwise.
  def json_exceeds_depth?(json, max_depth)
    depth = 0
    in_string = T.let(false, T::Boolean)
    escape = T.let(false, T::Boolean)
    i = 0
    len = json.bytesize

    while i < len
      byte = json.getbyte(i)

      if escape
        escape = false
        i += 1
        next
      end

      if byte == 0x5C # backslash
        escape = true if in_string
        i += 1
        next
      end

      if byte == 0x22 # double quote
        in_string = !in_string
        i += 1
        next
      end

      unless in_string
        if byte == 0x7B || byte == 0x5B # { or [
          depth += 1
          return true if depth > max_depth
        elsif byte == 0x7D || byte == 0x5D # } or ]
          depth -= 1
        end
      end

      i += 1
    end

    false
  end
end
