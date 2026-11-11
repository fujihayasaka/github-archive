# typed: true
# frozen_string_literal: true

# Subclasses of this class are intended to serve as namespaces for individual
# SecurityProducts to encapsulate business logic that *enables* or *disables* a
# given service. Is a user allowed to enable this service? Has their
# organization paid for it? Are our dependencies enabled?  And so on.
#
# Use it to make it easier to reason about our user interfaces, and
# to make it easier to reason about the moving parts that make up our products.
module SecurityProduct
  class Service
    extend T::Helpers

    abstract!

    # github/security-center#674:
    # As we are slowly moving feature enablement into SecurityProduct::ServiceManager,
    # blocking people from calling SecurityProduct::Service.enable for security features
    # that have completed the transition.
    SERVICES_BLOCKED_FROM_CALLING_ENABLEMENT_FUNCTIONS = T.let([
      "SecurityProduct::AdvancedSecurity",
      "SecurityProduct::CodeSecurity",
      "SecurityProduct::TokenScanning",
      "SecurityProduct::TokenScanningPushProtection"
    ].freeze, T::Array[String])

    sig { returns Repository }
    attr_reader :repository

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    sig(:final) { params(actor: User, options: SecurityProduct::ServiceManager::ServiceOptions).returns(Result) }
    def enable(actor:, options: {})
      raise NotImplementedError if SERVICES_BLOCKED_FROM_CALLING_ENABLEMENT_FUNCTIONS.include?(self.class.to_s)

      manager = SecurityProduct::ServiceManager.new(repository)
      symbol = SecurityProduct::ServiceManager::SYMBOLS.fetch(self.class)

      result = manager.toggle_services(actor, services_to_enable: [[symbol, options]])
      Result.new(result.error.nil?, result.error)
    end

    sig(:final) { params(actor: User, options: SecurityProduct::ServiceManager::ServiceOptions).returns(Result) }
    def disable(actor:, options: {})
      raise NotImplementedError if SERVICES_BLOCKED_FROM_CALLING_ENABLEMENT_FUNCTIONS.include?(self.class.to_s)

      manager = SecurityProduct::ServiceManager.new(repository)
      symbol = SecurityProduct::ServiceManager::SYMBOLS.fetch(self.class)

      result = manager.toggle_services(actor, services_to_disable: [[symbol, options]])
      Result.new(result.error.nil?, result.error)
    end

    # The following methods are to be overridden at will by subclasses.

    # How should `can_enable?` be used? This depends on your service; you are
    # free to implement your own `enable` logic. That said, I advise you to
    # consider `can_enable?` from the perspective of a user. Given this actor,
    # at this point in time, for this repository, can this service be enabled?
    sig { overridable.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_enable?(actor:, options:)
      Result.new(true)
    end

    sig { overridable.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def can_disable?(actor:, options:)
      Result.new(true)
    end

    # `on_enable` and `on_disable` should be where the actual configuration
    # data is persisted; ideally, these methods should not have to concern
    # themselves with whether the actor is authorized, or the repository is in
    # a valid state – since we check for that in `can_enable?`.

    # should return:
    # * Result.new(ToggledServiceCollection) with the set of services that were toggled as result of the call;
    #   use ToggledServiceCollection.empty if no services were toggled.
    # * Result.new(ToggledServiceCollection, :error_symbol) in case of error.
    sig { abstract.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_enable(actor:, options:)
    end

    # should return:
    # * Result.new(ToggledServiceCollection) with the set of services that were toggled as result of the call;
    #   use ToggledServiceCollection.empty if no services were toggled.
    # * Result.new(ToggledServiceCollection, :error_symbol) in case of error.
    sig { abstract.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def on_disable(actor:, options:)
    end

    # In general, disabling a service should result in an attached security configuration
    # being removed if that configuration had the service set as enabled. However, in
    # some very specific cases, we want to keep the configuration around, even if the
    # service is disabled. See overrides of this method for more details.
    sig { overridable.params(options: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def skip_removing_configuration_on_disable?(options:)
      false
    end

    # should return true or false
    sig { abstract.returns(T::Boolean) }
    def enabled?
    end

    # For some services, merely checking if they are enabled is not sufficient to determine if the ServiceManager
    # can skip an enablement attempt with the `skip_if_enabled` option set.
    #
    # This method provides a hook to ask the service to check the options hash and determine if the current
    # Service state reflects the options, returning true,  or if it the options differ, returning false.
    #
    # returns Boolean
    sig { overridable.params(options: T.untyped).returns(T::Boolean) }
    def enabled_with_options?(options: {})
      enabled?
    end

    # -- helpers
    sig(:final) { params(service_syms: Symbol, actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def enable_requirements(*service_syms, actor:, options:)
      options[:skip_if_enabled] = true
      SecurityProduct::ServiceManager.new(repository).toggle_services(
        actor,
        services_to_enable: service_syms.map do |sym|
          [sym, options]
        end,
        skip_instrumentation: true
      )
    end

    sig(:final) { params(service_syms: Symbol, actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def disable_dependents(*service_syms, actor:, options:)
      options[:skip_if_disabled] = true
      SecurityProduct::ServiceManager.new(repository).toggle_services(
        actor,
        services_to_disable: service_syms.map do |sym|
          [sym, options]
        end,
        skip_instrumentation: true
      )
    end

    sig(:final) { params(service_syms: Symbol, actor: User, options: T.untyped).returns(SecurityProduct::Result) }
    def enable_dependents(*service_syms, actor:, options:)
      options[:skip_if_enabled] = true
      SecurityProduct::ServiceManager.new(repository).toggle_services(
        actor,
        services_to_enable: service_syms.map do |sym|
          [sym, options]
        end,
        skip_instrumentation: true
      )
    end

    sig { abstract.returns(Symbol) }
    def to_sym
    end

    sig { abstract.returns(String) }
    def self.name
    end

    sig { overridable.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
    def self.error_to_message(symbol)
      case symbol
      when :security_configuration_enforced
        "An enforced security configuration prevented modifying #{self.name.downcase} enablement. Contact your organization owner for details."
      else
        "Failed to change #{self.name.downcase} status."
      end
    end

    private

    def log_timing
      unless FeatureFlag.vexi.enabled?(:security_products_enablement_timing_logging, repository, default: false)
        return yield
      end

      calling_class = self.class.to_s
      calling_method = caller_locations(1, 1)&.first&.base_label

      GitHub.logger.with_named_tags(
        "code.namespace": calling_class,
        "code.function": calling_method,
      ) do
        result = :unknown
        timer = ::Timer.start
        GitHub.logger.info("Start log_timing")
        result = yield
      ensure
        duration = timer.elapsed_ms
        log_context = { "gh.security_products_enablement.log_timing.time": duration }
        datadog_tags = %W[service:#{to_sym} method:#{calling_method}]

        error = $!
        if error
          log_context.update("exception.type": error.class.to_s, "exception.message": error.message)
          datadog_tags.concat(%W[result:error error:#{error.class.to_s.underscore}])
        else
          result_tag =
            case result
            when true, false, :unknown then result.to_s
            when SecurityProduct::Result
              value, error = result.to_a

              if error
                "error"
              else
                case value
                when true, false then value.to_s
                else "success"
                end
              end
            else "success"
            end

          datadog_tags.push("result:#{result_tag}")
        end

        GitHub.logger.info("Stop log_timing: #{result_tag}", log_context)
        GitHub.dogstats.distribution("security_products_enablement.log_timing.time", duration, tags: datadog_tags)
      end
    end
  end
end
