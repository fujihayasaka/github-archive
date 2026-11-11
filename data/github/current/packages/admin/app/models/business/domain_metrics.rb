# typed: strict
# frozen_string_literal: true

module Business::DomainMetrics
  extend ActiveSupport::Concern
  extend T::Helpers
  include Kernel

  class ScopeProxy
    include Business::DomainMetrics
    sig { returns(String) }; attr_accessor :method
    sig { returns(ActiveRecord::Relation) }; attr_accessor :scope
    sig { returns(T::Hash[Symbol, T.untyped]) }; attr_accessor :tags

    delegate :class, :==, to: :scope

    sig do
      params(
        scope: ActiveRecord::Relation,
        method: String,
        tags: T::Hash[Symbol, T.untyped],
      ).void
    end
    def initialize(scope, method, tags)
      @method = method
      @scope = scope
      @tags = tags
    end

    sig do
      params(
        method: T.untyped,
        args: T.untyped,
        kwargs: T.untyped,
        block: T.nilable(T.proc.returns(T.untyped))
      ).returns(T.untyped)
    end
    def method_missing(method, *args, **kwargs, &block)
      t0 = GitHub::Dogstats.monotonic_time
      result = T.unsafe(@scope).send(method, *args, **kwargs, &block) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
      return ScopeProxy.new(result, @method, @tags) if result.is_a?(ActiveRecord::Relation)
      domain_metrics(@method, tags.merge(t0:, scope: method))
      result
    end

    sig do
      params(
        method_name: T.any(String, Symbol),
        include_private: T::Boolean
      ).returns(T::Boolean)
    end
    def respond_to_missing?(method_name, include_private = false)
      @scope.respond_to?(method_name, include_private) || super
    end
  end

  # Adds a domain_metrics helper for capturing metrics for the business domain.
  #
  # Metrics collected:
  # - domain.count.enterprise_primitives: increments for each call of this method
  # - domain.call.enterprise_primitives distribution time for each method call
  #
  # This also includes the customer_category tag if the objeect either has a
  # customer_category or a business or organization.
  #
  # method: Name of the method call these metrics belong to
  # scope: Result is returned as a DomainMetrics::Scope to further track scope
  #   execution metrics. The execution of the block (producing the scope) is
  #   also tracked with a tag scope:build.
  # skip: Skips distribution metric for cases where the result will be skewed
  #   due to memoization for example
  # t0: Provide start time for the distribution timing. Also does not execute
  #   block
  # version: Defaults to 1. Increment for changes to the method to allow for
  #   comparison between different versions
  # Additional tags to apply to the dogstats metrics can be provided as additional
  # method call parameters.
  sig do
    params(
      method: T.untyped,
      tags: T.nilable(T::Hash[Symbol, T.untyped]),
      block: T.nilable(T.proc.returns(T.untyped))
    ).returns(T.untyped)
  end
  def domain_metrics(method, tags = nil, &block)
    tags = tags ? tags.dup : {}
    scope = tags.delete(:scope)
    t0 = tags.delete(:t0)
    version = tags.delete(:version) || 1
    customer_category = if respond_to?(:customer_category)
      send(:customer_category)
    elsif respond_to?(:business)
      send(:business)&.customer_category
    elsif respond_to?(:organization)
      send(:organization)&.customer_category
    end
    catalog_service = GitHub.context[:catalog_service].to_s.underscore.presence || "unknown"
    domain = tags.delete(:domain) || GitHub.packageowners.package_for_type(self.class)
    klass = tags.delete(:class) || self.class.name
    dogtags = [
      "calling_catalog_service:#{catalog_service}",
      "domain:#{domain}",
      "method:#{method}",
      "class:#{klass}",
      "customer_category:#{customer_category || "none"}",
      "version:#{version}",
      "scope:#{scope == true ? "build" : (scope || "none")}"
    ] + tags.map { |k, v| "#{k}:#{v}" }
    GitHub.dogstats.increment("domain.count.enterprise_primitives", tags: dogtags)
    if tags[:skip] && block_given?
      return yield
    end
    if t0.present?
      GitHub.dogstats.distribution_timing_since("domain.call.enterprise_primitives", t0, tags: dogtags)
      nil
    elsif block_given?
      result = GitHub.dogstats.distribution_time("domain.call.enterprise_primitives", tags: dogtags, &block)
      return domain_metrics_scope(result, method, tags.merge(calling_catalog_service: catalog_service, class: klass, customer_category: customer_category, domain: domain, version: version)) if scope
      result
    else
      nil
    end
  end

  # Returns a DomainMetrics::ScopeProxy.
  # For all methods producing a result a new domain_metric is recorded.
  # For all method calls producing a scope, another ScopeProxy is returned.
  sig do
    params(
      scope: ActiveRecord::Relation,
      method: T.untyped,
      tags: T.nilable(T::Hash[Symbol, T.untyped])
    ).returns(ScopeProxy)
  end
  def domain_metrics_scope(scope, method, tags = nil)
    ScopeProxy.new(scope, method.to_s, tags || {})
  end
end
