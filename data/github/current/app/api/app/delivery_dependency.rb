# typed: true
# frozen_string_literal: true

module Api::App::DeliveryDependency
  extend ActiveSupport::Concern

  include Api::App::CachingHelpers
  include Api::App::DeprecationHelpers
  include Api::App::ShortcodeDetectionHelper
  include Api::App::ProgrammaticFgpHeaderDecorator

  LocationStatusCodes = Set.new([201, 301, 302, 307]).freeze
  GITHUB_AUTHENTICATION_TOKEN_EXPIRATION_KEY = "GitHub-Authentication-Token-Expiration".freeze

  # Public: Deliver a serialized object to the client as JSON.
  #
  # serialize_method - Symbol name of the serializer method to use.
  # obj              - Any record serializable to JSON using the V3 serializer.
  # options          - Optional Hash that is passed to the serializer.
  #                    :status       - Integer of the HTTP Status, if it's
  #                                    different than 200.
  #                    :content_type - String Content-Type header if you want
  #                                    to deliver something other than JSON.
  #
  # Returns a String body to be used as the response of this request.
  def deliver(serialize_method, obj = nil, options = nil)
    if !serialize_method.is_a?(Symbol)
      obj = (serialize_method.respond_to?(:map!) ? serialize_method.first : serialize_method)
      raise "Needs serialize_method: #{obj.class.api_serializer_method.to_sym}"
    end

    if [nil, false].include?(obj)
      return deliver_error(404)
    end

    options ||= {}
    options.update(default_options)

    code = options.delete(:status) || 200
    status code

    if options[:anomaly_action]
      @meta["X-GitHub-Anomaly-Backend"] = "api"
      @meta["X-GitHub-Anomaly-Action"] = options[:anomaly_action]
    end

    unless @links.has_pagination?
      # The collection size can be defined in a number of different ways.
      # 1. Explicitly set paginator.collection_size in the API endpoint.
      #    Typically used with REST endpoints backed by GraphQL, as the object passed to the serializer
      #    is not always the one that has a #total_count method.
      #    Additionally, the GraphQL objects get cranky if you call #total_count outside of the API endpoints.
      # 2. Infer from #total_entries on the collection.
      #    This is typically used with paginated ActiveRecord relations and WillPaginate collections,
      #    or collections that have explicitly been made to quack like them.
      # 3. Infer from :total_count passed to the serializer.
      #    This is used when the API payload returns the collection in a Hash rather than a top-level Array,
      #    since in that case the collection to be paginated is passed as part of the hash, and we can't guess
      #    the key name.

      nested_key = options[:nested_pagination_key]
      if nested_key && obj.is_a?(Hash) && obj[nested_key].respond_to?(:total_entries)
        paginator.collection_size ||= obj[nested_key].total_entries
        options.delete(:nested_pagination_key)
      else
        paginator.collection_size ||= obj[:total_count] if obj.is_a?(Hash) && obj.key?(:total_count)
        paginator.collection_size ||= obj.total_entries if obj.respond_to?(:total_entries)
      end

      paginator.collection_size = [paginator.collection_size.to_i, pagination_capped_to_n_entries].min if pagination_capped_to_n_entries
      set_pagination_headers(skip_last_page_link: options.delete(:skip_last_page_link))
    end

    if Rails.env.test?
      env["github.pagination"]                      = @pagination                              if @pagination.present?
      env["github.oauth"]                           = @oauth                                   if @oauth.present?
      env["github.user"]                            = @current_user                            if @current_user.present?
      env["github.oauth_app"]                       = @current_app                             if @current_app.present?
      env["github.integration"]                     = @current_integration                     if @current_integration.present?
      env["github.integration_installation"]        = @current_integration_installation        if @current_integration_installation.present?
      env["github.parent_integration_installation"] = @current_parent_integration_installation if @current_parent_integration_installation.present?
      env["github.programmatic_access"]             = @current_programmatic_access             if @current_programmatic_access.present?
    end

    if @oauth
      @meta["X-OAuth-Scopes"] = @oauth.access_level.dup * ", "
      @meta["X-Accepted-OAuth-Scopes"] = accepted_scopes_string
      if @oauth.application
        @meta["X-OAuth-Client-Id"] = @oauth.application.key
      end

      if @oauth.expires_at
        @meta[GITHUB_AUTHENTICATION_TOKEN_EXPIRATION_KEY] = @oauth.expires_at.to_s
      end
    end

    if @current_programmatic_access && @current_programmatic_access.expires_at
      @meta[GITHUB_AUTHENTICATION_TOKEN_EXPIRATION_KEY] = @current_programmatic_access.expires_at.to_s
    end

    if GitHub.enterprise?
      @meta["X-GitHub-Enterprise-Version"] = GitHub.version_number
    elsif GitHub.multi_tenant_enterprise?
      @meta["X-GitHub-Enterprise-Version"] = "ghe.com"
    end

    options[:current_user] ||= @current_user

    skip_serialization = serialize_method == :raw
    custom_content_type = options.delete(:content_type)
    content_type = custom_content_type || default_content_type

    if !(custom_content_type || skip_serialization)
      tags = options.delete(:instrumentation_tags) || []

      serializer_options = Api::SerializerOptions.fill(options)
      serializer_options[:route] ||= request.env["sinatra.route"]
      serializer_options[:skip_strict_loading] ||= (request.post? || request.patch?)

      if nested_key && obj.is_a?(Hash) && obj.key?(nested_key)
        # Only serialize the nested array, but keep the overall shape
        serialized_nested = instrument_serialization(tags) do
          Api::Serializer.serialize(serialize_method, obj[nested_key], serializer_options)
        end
        # Then put the result back under the same nested key
        obj[nested_key] = serialized_nested
      else
        obj = instrument_serialization(tags) do
          Api::Serializer.serialize(serialize_method, obj, serializer_options)
        end
      end
    end

    if options[:audit_log_query_cost]
      @meta["X-AuditLog-Query-Cost"] = options[:audit_log_query_cost].to_s
    end

    if GitHub.multi_tenant_enterprise?
      if business = GitHub::CurrentTenant.get
        if block_suffixed_params?(obj, business: business, namespace: "Api::App::DeliveryDependency", blocking_enabled: true)
          status 404
          obj = { message: "Unable to complete request that contains suffixed values in the response payloads." }
        end
      end
    end

    if LocationStatusCodes.include?(code)
      url = (obj.is_a?(Hash) && obj[:url]) || options[:url]
      @meta["Location"] = url if url
    end

    pretty = user_agent.cli? || user_agent.browser?

    # For the special case where all conditions are met, there is no need to encode this object as JSON:
    #
    #   - no serializer method was invoked
    #   - the content type is specified by the caller (i.e. non-JSON content)
    #   - the received object is already a string
    #
    encoded_object_for_etag = if custom_content_type && skip_serialization && obj.is_a?(String)
      obj
    else
      encode_json(obj)
    end

    extra_newline = pretty ? "\n" : ""

    caching_options = {
      last_modified: options[:last_modified],
      etag: options[:etag],
      body: encoded_object_for_etag,
      max_age: options[:max_age],
      skip_caching_headers: options[:skip_caching_headers],
    }

    set_caching_headers! caching_options
    geo_block_list = (obj.is_a?(Hash) && obj[:geo_block_list]) || options[:geo_block_list]
    unless medias.empty?
      @meta["X-GitHub-Media-Type"] = medias.to_http_header
    end
    @meta["X-Geo-Block-List"] = geo_block_list if geo_block_list

    # JSON-P requests get send http 200, with http headers as a json envelope
    # around the json response
    if jsonp?
      status 200
      headers["Content-Type"] = "application/javascript; charset=utf-8"

      @meta["Link"]  = @links.to_meta if @links.present?
      @meta[:status] = code

      # JSONP responses need to decrement the remaining rate limit here.
      # because `after` block is too late (the limit is written into the JSON body, not only as a header).
      # Pass the code that _would have been_ used (jsonp always returns 200).
      increment_rate_limit_and_set_headers!(status_code: code)

      obj = nil if code == 204
      encode_jsonp(meta: response.headers.merge(@meta), data: obj, pretty: pretty) + extra_newline

    elsif code == 205
      # According to the HTTP spec, a response 'SHOULD' contain a content-type if
      # it has a response body. In other words, content-type is optional, and
      # if there is no response body, there is no reason to include it.
      # However, at the moment it's tricky to get Sinatra to remove the content-type
      # header altogether.
      content_type "text/plain"
      headers @meta if @meta.present?
      ""
    else
      # everyone else gets a sane json response
      headers["Content-Type"] = content_type
      headers @meta if @meta.present?
      set_deprecation_headers!
      headers["Link"] = @links.to_header if @links.present?

      body = if custom_content_type
        obj
      else
        # generate a new prettified response body if the client is a specific user agent
        encoded_object_for_body = pretty ? encode_json(obj, pretty: true) : encoded_object_for_etag
        encoded_object_for_body + extra_newline
      end

      if should_send_valid_permissions?
        value = permissions_header_for_request
        headers["X-Accepted-GitHub-Permissions"] = value unless value == :unsupported
      end

      code == 204 ? "" : body
    end
  end

  def default_options
    options = {}

    if (mimes = request.accept).present?
      options[:accept_mime_types] = mimes
    end

    media = medias.api
    options[:mime_params] = media&.api_params

    options[:global_id_selection] = global_id_selection

    options[:api_version] = @selected_api_version

    options[:serialize_login] = serialize_login_selection

    options
  end

  # Public: Deliver a serialized object to the client as JSON and halt.
  #
  # serialize_method - Symbol name of the serializer method to use.
  # obj              - Any record serializable to JSON using the V3 serializer.
  # options          - Optional Hash that is passed to the serializer.
  #                    :status       - Integer of the HTTP Status, if it's
  #                                    different than 200.
  #                    :content_type - String Content-Type header if you want
  #                                    to deliver something other than JSON.
  #
  # Delivers the response body and halts further processing.
  def deliver!(serialize_method, obj = nil, options = nil)
    halt deliver(serialize_method, obj, options)
  end

  def default_content_type
    "application/json; charset=utf-8"
  end

  # Public: Deliver a serialized object to the client as JSON.
  #
  # Same as:
  #
  #   deliver(:raw, foo, options)
  #
  def deliver_raw(obj, options = nil)
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do |_span|
      deliver(:raw, obj, options)
    end
  end

  # Public: Deliver an empty response to the client.
  #
  # Same as:
  #
  #   deliver(:raw, {}, options)
  #
  def deliver_empty(options = nil)
    deliver(:raw, {}, options)
  end

  # Public: Halt the request with a redirect.
  #
  # url               - The String URL to redirect to.
  # status            - The Integer HTTP status code to use for the response.
  # documentation_url - The String URL to include in the response body
  #                     identifying the location of documentation relevant to
  #                     the request/response (optional).
  #
  # Returns nothing.
  def deliver_redirect!(url, status:, documentation_url: "/rest/guides/best-practices-for-using-the-rest-api#follow-redirects")
    body = {
      message: "Moved Permanently",
      url: url,
      documentation_url: "#{GitHub.developer_help_url}#{documentation_url}",
    }

    options = {
      url: url,
      status: status,
    }

    halt deliver_raw(body, options)
  end

  def encode_json(object, **options)
    GitHub::JSON.yajl_encode(object, options)
  end

  def encode_jsonp(meta:, data:, pretty:)
    if varnished?
      # Start the response with "<" and set a "X-Iris-JSONP-With-ESI"
      # header so that varnish will process ESI tags. Also, escape any
      # "<" in the data so that we don't process user-supplied data,
      # e.g. a repository description like 'ha ha <esi:include src=bogus> ha ha'.

      headers["X-Iris-JSONP-With-ESI"] = "true"
      enable_esi = "<esi:remove></esi:remove>"

      meta = meta.merge \
        "X-RateLimit-Limit" => "<esi:include src='/_esi/jsonp_rate_limit/limit'/>",
        "X-RateLimit-Remaining" => "<esi:include src='/_esi/jsonp_rate_limit/remaining'/>",
        "X-RateLimit-Reset" => "<esi:include src='/_esi/jsonp_rate_limit/reset'/>",
        "X-RateLimit-Used" => "<esi:include src='/_esi/jsonp_rate_limit/used'/>",
        "X-RateLimit-Resource" => "<esi:include src='/_esi/jsonp_rate_limit/resource'/>"
      meta_json = encode_json(meta, pretty: pretty)
      data_json = encode_json(data, pretty: pretty).
        gsub("<", "\\u003c").
        gsub(">", "\\u003e")
      payload = '{"meta": %s, "data": %s}' % [meta_json, data_json]
    else
      enable_esi = ""
      payload = encode_json({ meta: meta, data: data }, pretty: pretty)
    end

    payload = payload.
      gsub("\u2028", '\u2028'). # github/github#6188
      gsub("\u2029", '\u2029')  # http://timelessrepo.com/json-isnt-a-javascript-subset

    "%s/**/%s(%s)" % [enable_esi, jsonp_callback, payload]
  end

  def jsonp_callback
    return @jsonp if defined?(@jsonp)

    return unless @jsonp = params["callback"]

    if @jsonp.is_a?(String) && @jsonp.valid_encoding? && !!(@jsonp =~ /\A[\w\.\[\]]+\z/)
      @jsonp.strip!
    else
      GitHub.dogstats.increment("github.encoding.jsonp_callback_invalid")
      params.delete("callback")
      message = "Invalid callback: #{@jsonp.inspect}"
      @jsonp  = nil
      deliver_error!(400, message: message, documentation_url: "/v3/#json-p-callbacks")
    end

    @jsonp
  end

  def jsonp?
    !!jsonp_callback
  end

  def varnished?
    env["HTTP_X_GITHUB_DYNAMIC_CACHE"] == "api"
  end

  DefaultModifiedTime = Time.utc(1970)

  def calc_last_modified(objects)
    return nil if objects.blank?
    modified =
      Array(objects).map do |o|
        if o && o.respond_to?(:last_modified_at)
          o.last_modified_at || DefaultModifiedTime
        else
          DefaultModifiedTime
        end
      end.max
    modified || raise(ArgumentError, "Invariant: no last-modified calculation found for objects")
  end

  def calc_last_modified_for_object(object)
    return nil if object.nil?

    if object.respond_to?(:last_modified_at)
      object.last_modified_at || DefaultModifiedTime
    else
      DefaultModifiedTime
    end
  end

  # Builds an API url from the current Rack environment without query
  # parameters.
  #
  # env - The Rack environment Hash.
  #
  # Returns a String URL.
  def url_without_query(env)
    url = request.scheme + "://"
    url << request.host

    if request.scheme == "https" && request.port != 443 ||
        request.scheme == "http" && request.port != 80
      url << ":#{request.port}"
    end

    if prefix = env[GitHub::Routers::Api::API_PATH]
      url << prefix
    end

    url << request.path
  end

  # Build a formatted string of scopes based on the current
  # accepted scopes array.
  #
  # Returns a String
  def accepted_scopes_string
    @accepted_scopes = %w(repo) if @accepted_scopes.nil?
    OauthAccessTokens::Domain.filter_public_scopes(@accepted_scopes).sort * ", "
  end

  def should_send_valid_permissions?
    using_fine_grained_actor?
  end

  def using_fine_grained_actor?
    @current_integration || @current_programmatic_access
  end

  private

  # Instrument the serialization of an object
  #
  # Accepts a default array of tags to be added
  # Requires a block to be passed to instrument
  #
  # Returns the serialized Object
  def instrument_serialization(default_tags)
    initial_query_count = GitHub::MysqlInstrumenter.query_count

    service_name = GitHub::TaggingHelper.catalog_service(env)
    GitHub::TaggingHelper.add_tag(default_tags, GitHub::TaggingHelper::CATALOG_SERVICE_TAG, service_name)

    # We should have all the data before needing to serialize, so there should be
    # no database queries made by the time we get here
    obj = Api::InstrumentSegment.call(env, "api.request.serialize", tags: default_tags) do
      yield
    end

    # We only want a specific subset of tags to be sent for the api.request.serialize.queries metric
    db_tags = [
      "http_method:#{env['REQUEST_METHOD']}",
      "api_app:#{env['process.api.controller']}",
      "route_pattern:#{Api::App.route_pattern(env)}",
      "#{GitHub::TaggingHelper::CATALOG_SERVICE_TAG}:#{service_name}"
    ]

    final_query_count = GitHub::MysqlInstrumenter.query_count
    diff = final_query_count - initial_query_count
    GitHub.dogstats.count("api.request.serialize.queries", diff, tags: db_tags)

    obj
  end
end
