# typed: true
# frozen_string_literal: true

module GitHub
  class CurrentTenant
    # Add newly provisioned stafftools tenants here
    # These are provisioned stafftools tenant slugs
    # In the future these may come from an API e.g Tenant Metadata Service etc.
    PRODUCTION_STAFFTOOLS_TENANTS = %w[
      stafftoolswus2
      stafftools-prodweu01
      stafftools-prodsdc01
      stafftools-prodae01
      stafftools-prodcus01
      stafftools-testcnc01
    ].freeze

    DEVELOPMENT_STAFFTOOLS_TENANTS = %w[stafftools-proxima-tenant].freeze

    def self.reset(force: false)
      return unless force || reset?
      Thread.current.thread_variable_set(:gh_current_tenant, nil)
      Thread.current.thread_variable_set(:gh_current_tenant_unscope, nil)
    end

    def self.reset?
      return false unless GitHub.multi_tenant_enterprise?
      return false unless GitHub.flipper[:reset_tenant_context].enabled?
      true
    end

    def self.get
      Thread.current.thread_variable_get(:gh_current_tenant)
    end

    def self.remove
      set(nil)
    end

    def self.set(business, unset_after_block: block_given?)
      Thread.current.thread_variable_set(:gh_current_tenant, business)
      yield if block_given?
    ensure
      remove if unset_after_block
    end

    def self.unscope
      original = Thread.current.thread_variable_get(:gh_current_tenant_unscope)
      Thread.current.thread_variable_set(:gh_current_tenant_unscope, true)
      yield
    ensure
      Thread.current.thread_variable_set(:gh_current_tenant_unscope, original)
    end

    def self.rescope
      Thread.current.thread_variable_set(:gh_current_tenant_unscope, false)
    end

    def self.unscoped?
      return true unless GitHub.multi_tenant_enterprise?
      Thread.current.thread_variable_get(:gh_current_tenant_unscope)
    end

    # Temporarily suspends the current tenant context, executes the provided block of code,
    # and then restores the original tenant context. This is useful when you need to perform
    # some operation that isn't tied to the current tenant.
    #
    # The method first saves the current tenant and scope to local variables. It then yields
    # control to the provided block of code. After the block has finished executing, the
    # original tenant and scope are restored, ensuring that subsequent code continues to
    # operate in the original tenant context.
    def self.restore_tenant_context
      original_scope = Thread.current.thread_variable_get(:gh_current_tenant_unscope)
      original_tenant = Thread.current.thread_variable_get(:gh_current_tenant)
      yield
    ensure
      Thread.current.thread_variable_set(:gh_current_tenant_unscope, original_scope)
      Thread.current.thread_variable_set(:gh_current_tenant, original_tenant)
    end

    # All stamps will have a stafftools tenant that will be named stafftools<stamp>.<domain>
    # e.g stafftoolswus2.ghe.com is the stafftools tenant for staffship
    def self.stafftools_tenant?
      return false unless GitHub.multi_tenant_enterprise?
      return false if get.nil?
      get.stafftools_tenant?
    end

    def self.logging_context
      return {} unless GitHub.multi_tenant_enterprise?
      {
        "gh.tenant_set" => get.present?,
        "gh.tenant.id" => get&.id,
        "gh.tenant.slug" => get&.slug,
        "gh.tenant.query_scoping" => unscoped? ? "disabled" : "enabled",
      }
    end

    def self.hydro_context
      {
        "tenant_id" => get&.id&.to_s,
        "tenant_name" => get&.slug,
      }
    end

    def self.metrics_tags
      [
        "tenant_set:#{get.present?}",
        "query_scoping:#{unscoped? ? "disabled" : "enabled"}",
      ]
    end

  end
end
