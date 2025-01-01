# typed: true
# frozen_string_literal: true

module Api::App::TenantContextDependency
  extend T::Helpers
  requires_ancestor { Api::App }
  requires_ancestor { Api::App::FindersDependency }

  class TenantContextResolutionError < StandardError; end

  # Internal
  def current_tenant
    return unless GitHub.multi_tenant_enterprise?
    return unless GitHub.flipper[:log_current_tenant].enabled?
    GitHub::CurrentTenant.get
  end

  def infer_tenant_from_repo
    return unless GitHub.multi_tenant_enterprise? && GitHub.flipper[:internal_api_infer_tenant].enabled?
    return if GitHub::CurrentTenant.get.present?

    return unless repo = find_repo
    return unless tenant = Business.find_by(id: repo.tenant_id)

    GitHub::CurrentTenant.set(tenant)
    GitHub::CurrentTenant.rescope
  end

  def unscope_request_for_internal_services?
    # Return false if the request is a tenant request.
    return false if GitHub::CurrentTenant.get.present?

    # Validate configuration allows unscoping in this environment.
    return false unless GitHub.proxima_internal_api_request_scoping_disabled?

    # Only requests targeting the internal-api host are allowed to be unscoped.
    # This includes both public and internal API endpoints.
    GitHub::Routers::Api.internal_api_host?(request.host)
  end

  def call_original_block(method_name, original_block_arity, *args)
    if original_block_arity != 0
      T.unsafe(self).send(method_name, *args)
    else
      send(method_name)
    end
  end

  def call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block_arity, *args, exempt_from_tenant_context_requirement: false, temporarily_exempt_from_tenant_context_requirement: false, resolve_tenant_context_defined: false)
    emit_tenant_context_metrics(
      verb,
      path,
      exempt_from_tenant_context_requirement: exempt_from_tenant_context_requirement,
      temporarily_exempt_from_tenant_context_requirement: temporarily_exempt_from_tenant_context_requirement,
      resolve_tenant_context_defined: resolve_tenant_context_defined)

    T.unsafe(self).call_original_block(method_name, original_block_arity, *args)
  end

  private def validate_tenant_context_resolver(verb, path, resolver_symbol)
    unless self.respond_to?(resolver_symbol)
      raise TenantContextResolutionError, "Api path, #{verb} #{path}, defines a tenant context resolver, but the method, #{resolver_symbol}, does not exist."
    end
  end

  private def log_nil_tenant_context(resolver_response)
    GitHub.logger.warn("Could not find a tenant to resolve for #{resolver_response.class}.", {
      "code.namespace": self.class.name&.underscore,
      "code.function": "handle_tenant_context_requirement",
    })
  end

  private def log_tenant_context_mismatch(current_tenant, resolved_tenant)
    GitHub.logger.warn("Current tenant does not match resolved tenant and will be overwritten.", {
      "code.namespace": self.class.name&.underscore,
      "code.function": "handle_tenant_context_requirement",
      "gh.current_tenant.slug": current_tenant.slug,
      "gh.resolved_tenant.slug": resolved_tenant.slug,
    })
  end

  private def emit_tenant_context_metrics(verb, path, exempt_from_tenant_context_requirement: false, temporarily_exempt_from_tenant_context_requirement: false, resolve_tenant_context_defined: false)
    return unless GitHub.multi_tenant_enterprise?

    controller = GitHub::TaggingHelper.controller(request.env)
    internal_api_host = !!GitHub::Routers::Api.internal_api_host?(request.host)

    processor_tags = [
      "catalog_service:#{logical_service}",
      "controller:#{controller}",
      "action:#{path}",
      "internal_api_host:#{internal_api_host}",
      "api_verb:#{verb}",
      "tenant_context_requirement_temporarily_exempt:#{temporarily_exempt_from_tenant_context_requirement}",
      "tenant_context_requirement_exempt:#{exempt_from_tenant_context_requirement}",
      "resolve_tenant_context_defined:#{resolve_tenant_context_defined}"
    ]
    tags = GitHub::CurrentTenant.metrics_tags + processor_tags
    GitHub.dogstats.increment("tenant_context.sinatra_api", tags: tags)
  end

  module ClassMethods
    def handle_tenant_context_requirement(verb, path, options, &original_block)
      return original_block unless GitHub.multi_tenant_enterprise?

      method_name = "handle tenant context requirement for route #{verb} #{path}"
      define_method_with_duplicate_check(method_name, &original_block)

      resolver_symbol = options[:resolve_tenant_context]

      ->(*args) {
        T.bind(self, Api::App)

        validate_tenant_context_resolver(verb, path, resolver_symbol)
        resolver_response = GitHub::CurrentTenant.unscope { send(resolver_symbol) }

        unless resolver_response.is_a?(Business)
          log_nil_tenant_context(resolver_response)
          return T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args, resolve_tenant_context_defined: true)
        end

        current_tenant = GitHub::CurrentTenant.get
        if current_tenant != resolver_response
          log_tenant_context_mismatch(current_tenant, resolver_response) if current_tenant.present?
          GitHub::CurrentTenant.set(resolver_response)
        end

        T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args, resolve_tenant_context_defined: true)
      }
    end

    # This method returns a maybe-modified block that tenant unscopes the route
    def route_unscoped(verb, path, &original_block)
      return original_block unless GitHub.multi_tenant_enterprise?

      method_name = "unscoped route #{verb} #{path}"
      define_method_with_duplicate_check(method_name, &original_block)

      ->(*args) {
        T.bind(self, Api::App)
        return T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args) unless unscope_request_for_internal_services?

        GitHub::CurrentTenant.unscope do
          T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args, exempt_from_tenant_context_requirement: true)
        end
      }
    end

    def route_unscoped_until(verb, path, until_date, &original_block)
      return original_block unless GitHub.multi_tenant_enterprise?

      until_date_parsed =
        case until_date
        when Date then until_date
        else
          Date.parse(until_date)
        end

      method_name = "temporary unscoped route #{verb} #{path}"
      define_method_with_duplicate_check(method_name, &original_block)

      ->(*args) {
        T.bind(self, Api::App)
        exempted = until_date_parsed <= Date.today &&
          unscope_request_for_internal_services?
        return T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args) unless exempted

        GitHub::CurrentTenant.unscope do
          T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args, temporarily_exempt_from_tenant_context_requirement: true)
        end
      }
    end

    def route_with_tenant_context_metrics(verb, path, &original_block)
      return original_block unless GitHub.multi_tenant_enterprise?

      method_name = "send tenant context metrics #{verb} #{path}"
      define_method_with_duplicate_check(method_name, &original_block)

      ->(*args) {
        T.bind(self, Api::App)

        T.unsafe(self).call_original_block_with_tenant_context_metrics(verb, path, method_name, original_block.arity, *args)
      }
    end

    private def define_method_with_duplicate_check(method_name, &block)
      T.bind(self, Module)

      if method_defined?(method_name)
        raise ArgumentError, "Duplicate method name: #{method_name}"
      else
        define_method(method_name, &block)
      end
    end
  end

  mixes_in_class_methods(ClassMethods)
end
