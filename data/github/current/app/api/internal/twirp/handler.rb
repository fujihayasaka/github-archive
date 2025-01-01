# typed: true
# frozen_string_literal: true

# Abstract base class for Twirp handler classes.
class Api::Internal::Twirp::Handler
  include GitHub::ServiceMapping
  extend T::Sig

  attr_reader :current_repo, :current_user, :env

  # Public: Determines whether the current request is allowed for the given client name,
  # identified by the HMAC key used to sign requests.
  #
  # By default requests are disallowed for all clients.
  #
  # See Api::Internal::Twirp::ClientAccess for more information.
  #
  # client_name - The client name as a String.
  # env - The Twirp environment as a Hash.
  #
  # Returns a boolean.
  def allow_client?(client_name, env)
    self.class.allowed_clients.include?(client_name)
  end

  # Public: Check if a current repo has been set.
  #
  # Needed by Platform::Authorization.
  #
  # Returns a boolean.
  def current_repo_loaded?
    current_repo.present?
  end

  module ReportTwirpErrorsToDatadog
    UNKNOWN_METHOD = "unknown"

    def error_response(twerr, env)
      ruby_method = env[:ruby_method] || UNKNOWN_METHOD

      error_tags = [
        "code:#{twerr.code}",
        "handler:#{@handler.class.name&.underscore}",
        "service:#{@handler.service.name&.underscore}",
        "ruby_method:#{ruby_method}",
      ]

      GitHub.dogstats.increment("twirp.response.error", tags: error_tags)

      super
    end
  end

  module CallRpcWithDatabaseSelection
    # Override twirp-ruby's `#call_handler` with our own database selection logic.
    # The library doesn't provide an "around-hook" option, so we're hacking it.
    # @see TODO open an issue on twirp-ruby
    def call_handler(env)
      write_connection_methods = @handler.class.connected_to_writing_list
      connection_role = if !write_connection_methods.nil? && write_connection_methods.include?(env[:ruby_method].to_sym)
        :writing
      else
        :reading
      end

      ActiveRecord::Base.connected_to(role: connection_role) do
        super
      end
    end
  end

  module HandleTenantContextRequirement
    extend T::Helpers

    requires_ancestor { Kernel }
    extend T::Sig

    sig { params(env: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
    def call_handler(env)
      return super unless GitHub.multi_tenant_enterprise?

      ruby_method = env[:ruby_method] # method on the handler to handle this rpc request

      if exempt?(ruby_method) || temporary_exemption_active?(ruby_method)
        GitHub::CurrentTenant.unscope do
          emit_tenant_context_metrics(ruby_method)
          return super
        end
      end

      unless resolve_tenant_context?(ruby_method)
        emit_tenant_context_metrics(ruby_method)
        return super
      end

      resolver_response = GitHub::CurrentTenant.unscope { @handler.class.tenant_context_resolver.call(env[:input], env) }

      return resolver_response if resolver_response.is_a?(Twirp::Error)

      if !resolver_response.is_a?(Business)
        log_nil_tenant(resolver_response)
        emit_tenant_context_metrics(ruby_method)
        return super
      end

      current_tenant = GitHub::CurrentTenant.get

      if current_tenant != resolver_response
        log_mismatch(current_tenant, resolver_response) if current_tenant.present?
        GitHub::CurrentTenant.set(resolver_response)
      end

      emit_tenant_context_metrics(ruby_method)
      super
    end

    sig { params(ruby_method: Symbol).void }
    def emit_tenant_context_metrics(ruby_method)
      handler_tags = [
        "handler:#{@handler.class.name&.underscore}",
        "service:#{@handler.service.name&.underscore}",
        "method:#{ruby_method}",
        "tenant_context_requirement_exempt:#{exempt?(ruby_method)}",
        "tenant_context_requirement_temporarily_exempt:#{temporary_exemption_active?(ruby_method)}",
        "resolve_tenant_context_defined:#{resolve_tenant_context?(ruby_method)}",
      ]

      tags = GitHub::CurrentTenant.metrics_tags + handler_tags
      GitHub.dogstats.increment("tenant_context.twirp_handlers", tags: tags)
    end

    sig { params(ruby_method: Symbol).returns(T.nilable(T::Boolean)) }
    def resolve_tenant_context?(ruby_method)
      return true if @handler.class.tenant_context_resolver && @handler.class.tenant_context_resolver_endpoints.empty?
      return true if @handler.class.tenant_context_resolver && @handler.class.tenant_context_resolver_endpoints.include?(ruby_method)

      false
    end

    sig { params(ruby_method: Symbol).returns(T.nilable(T::Boolean)) }
    def exempt?(ruby_method)
      return true if @handler.class.exempt_from_tenant_context_requirement? && @handler.class.exempt_from_tenant_context_requirement_endpoints.empty?
      return true if @handler.class.exempt_from_tenant_context_requirement? && @handler.class.exempt_from_tenant_context_requirement_endpoints.include?(ruby_method)

      false
    end

    sig { params(ruby_method: Symbol).returns(T.nilable(T::Boolean)) }
    def temporary_exemption_active?(ruby_method)
      return true if @handler.class.temporarily_exempt_from_tenant_context_requirement? && @handler.class.temporarily_exempt_from_tenant_context_requirement_endpoints.empty?
      return true if @handler.class.temporarily_exempt_from_tenant_context_requirement? && @handler.class.temporarily_exempt_from_tenant_context_requirement_endpoints.include?(ruby_method) && @handler.class.temporary_exemption_active?

      false
    end

    sig { params(resolver_response: T.untyped).void }
    def log_nil_tenant(resolver_response)
      GitHub.logger.warn("Could not find a tenant to resolve for #{resolver_response.class}", {
        "code.namespace": self.class.name.underscore,
        "code.function": __method__,
      })
    end

    sig { params(current_tenant: T.untyped, resolver_response: T.untyped).void }
    def log_mismatch(current_tenant, resolver_response)
      GitHub.logger.warn("Current tenant does not match resolved tenant. Overwriting current tenant.", {
        "code.namespace": self.class.name.underscore,
        "code.function": __method__,
        "gh.current_tenant.slug": current_tenant.slug,
        "gh.resolved_tenant.slug": resolver_response.slug,
      })
    end
  end

  class ::Twirp::Service
    prepend HandleTenantContextRequirement
    prepend CallRpcWithDatabaseSelection
    prepend ReportTwirpErrorsToDatadog
  end

  # Public: Instantiates a service for this handler and memoizes the result.
  #
  # Returns a Twirp::Service subclass instance.
  def service
    @service ||= begin
      service_instance = self.class.service_class.new(self)
      auth_routines = self.class.access_allowed_for
      # First, queue up some general access checks unless they're opted out of
      auth_routines.include?(:client) && service_instance.before do |rack_env, env|
        Api::Internal::Twirp::ClientAccess.call(service_instance, self, rack_env, env)
      end
      auth_routines.include?(:user) && service_instance.before do |rack_env, env|
        Api::Internal::Twirp::UserAccess.call(service_instance, self, rack_env, env)
      end
      # Then, queue up the handler's own before_rpc hook
      service_instance.before do |rack_env, env|
        rack_env["twirp.method"] = "#{service_instance.name}/#{env[:rpc_method]}"
        before_rpc(rack_env, env)
      end
      service_instance
    end
  end

  # This is called before the rpc method, but after authorization.
  # Override it to add custom before-logic to a service.
  def before_rpc(rack_env, env)
    # In Proxima, all internal services can optionally pass in the X-Serialize-Login to
    # indicate that the response should include either login or display_login of the user or
    # either name_with_owner or name_with_display_owner of the repo
    if GitHub.multi_tenant_enterprise?
      env[:serialize_login_selection] = serialize_login_selection(rack_env)
    end
  end

  class << self
    # @return [Array<String>] A list of client names to explicitly allow
    attr_reader :allowed_clients
  end

  # Call this method in a subclass to hook up default authorization routines for
  # user-based access or client application-based application.
  #
  # @param access_methods [Array<Symbol>] May include `:user` and/or `:client`
  # @param require_user_token [Boolean] If true, requests will be rejected unless UserAccess can identify a user from the token header
  # @param allowed_clients [Array<String>] A list of client names to explicitly allow.
  def self.allow_access_for(*access_methods, require_user_token: false, allowed_clients: [])
    @require_user_token = require_user_token
    @access_allowed_for = access_methods
    @allowed_clients = allowed_clients
  end

  # @return [Array<Symbol>] Auth routines to use for this handler
  def self.access_allowed_for
    @access_allowed_for || raise("#{self} needs `allow_access_for ...` in its class definition (eg, `allow_access_for :user, :client`)")
  end

  def self.handles_service(service_class)
    @service_class = service_class
  end

  def self.service_class
    @service_class || raise(ArgumentError, "#{self} must be connected to a Twirp::Service class with `handles_service(...)`")
  end

  def self.require_user_token?
    @require_user_token
  end

  # Call this method in a subclass to configure a list of RPCs
  # that will need ActiveRecord :writing connections
  def self.connected_to_writing_for(*remote_procedure_calls)
    @require_write_connections = remote_procedure_calls
  end

  def self.connected_to_writing_list
    @require_write_connections
  end

  sig { returns(T.nilable(Proc)) }
  def self.tenant_context_resolver
    @tenant_context_resolver
  end

  sig { returns(T::Array[Symbol]) }
  def self.tenant_context_resolver_endpoints
    @tenant_context_resolver_endpoints || []
  end

  sig { returns(T::Array[Symbol]) }
  def self.exempt_from_tenant_context_requirement_endpoints
    @exempt_from_tenant_context_requirement_endpoints || []
  end

  sig { returns(T::Array[Symbol]) }
  def self.temporarily_exempt_from_tenant_context_requirement_endpoints
    @temporarily_exempt_from_tenant_context_requirement_endpoints || []
  end

  sig { returns(T.nilable(T::Boolean)) }
  def self.temporary_exemption_active?
    @temporarily_exempt_from_tenant_context_requirement_until && Date.today <= @temporarily_exempt_from_tenant_context_requirement_until
  end

  sig { returns(T.nilable(T::Boolean)) }
  def self.exempt_from_tenant_context_requirement?
    @exempt_from_tenant_context
  end

  sig { returns(T.nilable(T::Boolean)) }
  def self.temporarily_exempt_from_tenant_context_requirement?
    @temporarily_exempt_from_tenant_context
  end

  sig { returns(T::Array[Symbol]) }
  def self.tenant_context_requirement_used_only_values
    @tenant_context_requirement_used_only_values ||= []
  end

  sig { returns(T::Boolean) }
  def self.tenant_context_requirement_empty_only_used
    @tenant_context_requirement_empty_only_used ||= false
  end

  sig { params(only: T::Array[Symbol]).void }
  def self.exempt_from_tenant_context_requirement(only: [])
    self.check_tenant_context_requirement_only_values(only)
    @exempt_from_tenant_context = true
    @exempt_from_tenant_context_requirement_endpoints = only
  end

  sig { params(until_date: T.untyped, only: T::Array[Symbol]).void }
  def self.temporarily_exempt_from_tenant_context_requirement(until_date:, only: [])
    self.check_tenant_context_requirement_only_values(only)
    @temporarily_exempt_from_tenant_context_requirement_until = parse_until_date(until_date)
    @temporarily_exempt_from_tenant_context = true
    @temporarily_exempt_from_tenant_context_requirement_endpoints = only
  end

  sig { params(only: T::Array[Symbol], block: T.proc.params(req: T.untyped, _env: T.untyped).void).void }
  def self.resolve_tenant_context(only: [], &block)
    self.check_tenant_context_requirement_only_values(only)
    @tenant_context_resolver = block
    @tenant_context_resolver_endpoints = only
  end

  # Ensures that the same "only" value is not used in more than one tenant exemption or tenant resolution rule.
  # Also ensures that only one tenant exemption or tenant resolution rule can have an empty "only" array.
  sig { params(only: T::Array[Symbol]).void }
  def self.check_tenant_context_requirement_only_values(only)
    error_message = "No other rules are permitted because a tenant exemption or tenant resolution rule with an empty 'only' array has been defined."

    if only.empty?
      raise ArgumentError, error_message if tenant_context_requirement_used_only_values.any? || tenant_context_requirement_empty_only_used
      @tenant_context_requirement_empty_only_used = true
      return
    end

    raise ArgumentError, error_message if tenant_context_requirement_empty_only_used

    only.each do |value|
      if tenant_context_requirement_used_only_values.include?(value)
        raise ArgumentError, "'#{value}' has already been used in another tenant exemption or tenant resolution rule."
      else
        tenant_context_requirement_used_only_values << value
      end
    end
  end

  sig { params(until_date: T.untyped).returns(Date) }
  def self.parse_until_date(until_date)
    case until_date
    when Date
      until_date
    when String
      begin
        Date.parse(until_date)
      rescue ArgumentError
        raise ArgumentError, "String provided is not a valid date format"
      end
    else
      # allow Sorbet to reach the code since we declared `until_date` to be untyped
      raise TypeError, "until_date must be a Date or String, got #{until_date.class}"
    end
  end

  private

  # Private: Find the first non-empty (non-zero) ID argument.
  #
  # Go uses 0 for empty int values, so we need to discard them.
  #
  # Returns an Integer if a non-empty ID is found, nothing
  # otherwise.
  def id_argument(*possible_ids)
    provided_ids = possible_ids.compact
    provided_ids.detect { |id| id > 0 }
  end

  # Private: Allow internal services to define how login/NWO is serialized, whether to render unique or display
  # values according to their needs, per request, using the `X-Serialize-Login` header.
  def serialize_login_selection(rack_env)
    return :default unless GitHub.multi_tenant_enterprise?
    return :default unless GitHub.proxima_internal_api_unique_logins_required?
    case rack_env["HTTP_X_SERIALIZE_LOGIN"]
    when "unique"
      :unique
    when "display"
      :display
    else
      :default
    end
  end
end
