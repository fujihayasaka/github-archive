# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module GitHub
  module ServiceMapping
    extend T::Helpers
    include Kernel

    UNKNOWN_SERVICE = "unknown"
    SERVICE_PREFIX = "github"

    HASH_SALT = "github is home 4 all developers!".freeze

    # Removes the catalog_service from Failbot's context.
    def self.remove_failbot_catalog_service!
      Failbot.context.each do |context|
        context.delete("catalog_service") || context.delete(:catalog_service)
      end
    end

    module ClassMethods
      include Kernel
      extend T::Helpers

      # public: Define a service mapping for this class.
      #
      # note: DEPRECATED
      # This method was a stop gap measure to support controllers which serviced requests for
      # multiple logical services. If you find your controller handles requests for more than
      # one logical service, please refactor into multiple controllers instead of using this method.
      #
      # service_name - the name of the service
      # only - an allowlist of methods affected by this service mapping.
      #        An empty list means the service mapping will be the default for the class.
      def map_to_service(service_name, only: [])
        service_name = service_name.to_sym
        @default_service_mapping = service_name if only.empty?

        @services ||= Set.new
        @services << service_name

        @service_method_mappings ||= {}

        only.each do |method|
          method = method.to_sym
          @service_method_mappings[method] = service_name
        end
      end

      # public: Report the service mapping for the class or method.
      #
      # method - the method whose service mapping we want.
      #          A nil method means we want the default service mapping for the class.
      def service_mapping(method = nil, serviceowners: nil)
        serviceowners ||= GitHub.serviceowners

        # Clear the cache if we see a new serviceowners object.
        if @service_mapping_serviceowners && @service_mapping_serviceowners != serviceowners
          @service_mapping = {}
        else
          @service_mapping ||= {}
        end

        @service_mapping[method] ||= if method && @service_method_mappings &&
                                        (method_mapping = @service_method_mappings[method.to_sym])
          method_mapping
        # GraphQL types are classes _or_ modules, but GraphQL fields are _instances_;
        # make sure the object is a module before looking for a serviceowner by its path.
        elsif self.is_a?(Module) &&
              (file_mapping = serviceowners&.service_for_class(self))
          file_mapping
        else
          @default_service_mapping
        end
      end

      def services(prefix: false)
        return [] unless @services

        services = @services.to_a
        return services unless prefix

        services.sort.map { |service| "#{SERVICE_PREFIX}/#{service}" }
      end

      def any_service_method_mappings?
        return false unless @service_method_mappings

        @service_method_mappings.any?
      end
    end

    mixes_in_class_methods(ClassMethods)

    # public: Record the service mapping in all relevant contexts.
    #
    # keep this in sync with GitHub::Middleware::Stats#add_service_mapping to ensure unknown services
    # are always consistently labelled.
    #
    # @param env [Hash] A Rack env hash (if `nil`, `self.env` will be used if it's available)
    def push_service_mapping_context(env: nil, &block)
      # If we don't have serviceowners support enabled, don't push e.g. catalog_service:github/unknown
      # everywhere unnecessarily.
      if !GitHub.serviceowners
        context = {}
        context = GitHub.logger.with_named_tags(context, &block) if block_given?
        return context
      end

      current_service_mapping = logical_service

      # tag the service mapping in the rack env if available, or whatever env hash we find
      env ||= self.respond_to?(:env) && T.unsafe(self).env
      if env
        env[GitHub::TaggingHelper::PROCESS_SERVICE_KEY] = current_service_mapping
      end

      context = { catalog_service: current_service_mapping }

      # Just push our contexts without cleanup. Popping a context could easily result in
      # the wrong data being popped. This way we leak our data like everyone else and
      # rely on the process running to reset things.
      Audit.context.push(context)
      GitHub.context.push(context)
      Failbot.push(context)
      GitHub.current_span&.add_attributes(context.stringify_keys)

      # config/initializers/query_log_tags.rb pulls the catalog_service off of th
      # ActiveSupport::ExecutionContext and adds it to the query log tags.
      ActiveSupport::ExecutionContext.set(**context)

      # Both `ApplicationController` and `Api::App` implement a `log_data` method which is
      # expected to be a hash representing data attributes which will be sent to the request
      # logger.
      #
      # Otherwise, check the given Rack env, if there is one.
      log_data = (self.respond_to?(:log_data) && T.unsafe(self).log_data) ||
        (env && env[Rack::RequestLogger::APPLICATION_LOG_DATA])

      if log_data
        log_data.merge!(context)
      end

      log_context = context.except(:catalog_service)
      log_context["gh.catalog_service"] = context[:catalog_service]
      GitHub.logger.with_named_tags(log_context, &block) if block_given?
    end

    # A cache of { String => Hash } for reusing service contexts
    ALL_SERVICE_CONTEXTS = Hash.new { |h, k| h[k] = { catalog_service: k } }
    private_constant :ALL_SERVICE_CONTEXTS

    # A cache of { Symbol => String } for reusing catalog service names
    ALL_CATALOG_SERVICE_NAMES = Hash.new { |h, k| h[k] = "#{GitHub::ServiceMapping::SERVICE_PREFIX}/#{k}" }
    private_constant :ALL_CATALOG_SERVICE_NAMES

    # Add service mapping context to block, for a GraphQL call.
    # Instead of being called once-ish per request,
    # this is called over and over during a GraphQL query.
    def self.push_graphql_service_mapping_context(graphql_schema_member, graphql_query_ctx)
      catalog_service_name = catalog_service_name(graphql_schema_member.service_mapping)

      # Overwrite the service name in GraphQL context.
      # GraphQL error handlers will pull it out of here and add it to Failbot as needed.
      graphql_query_ctx[:current_catalog_service] = catalog_service_name

      graphql_query_ctx[:catalog_services] ||= Set.new
      graphql_query_ctx[:catalog_services] << catalog_service_name

      # Also use `.context.push(ctx)` so that `Failbot.report` calls are tagged
      failbot_ctx = ALL_SERVICE_CONTEXTS[catalog_service_name]

      ActiveSupport::ExecutionContext.set(**failbot_ctx) do
        Audit.context.push(failbot_ctx) do
          GitHub.context.push(failbot_ctx) do
            Failbot.push(failbot_ctx) do
              yield
            end
          end
        end
      end
    end

    # public: The fully qualified logical service name for a given service symbol
    def self.catalog_service_name(service_name_symbol)
      ALL_CATALOG_SERVICE_NAMES[service_name_symbol || UNKNOWN_SERVICE]
    end

    # public: The fully qualified logical service name corresponding to the current class and method.
    def logical_service
      method = respond_to?(:service_mapping_method) ? T.unsafe(self).service_mapping_method : T.let(T.unsafe(nil), T.untyped)
      ServiceMapping.catalog_service_name(self.class.service_mapping(method))
    end

    # public: Hashing the logical service name
    def logical_service_hash
      if logical_service.present?
        Digest::SHA256.hexdigest("#{HASH_SALT}#{logical_service}")
      end
    end
  end
end
