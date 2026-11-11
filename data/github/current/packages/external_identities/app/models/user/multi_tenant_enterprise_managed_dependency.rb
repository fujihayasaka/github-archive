# typed: false
# frozen_string_literal: true

module User::MultiTenantEnterpriseManagedDependency
  NON_ENTERPRISE_MANAGED_BUSINESS_ID = 0

  class NullTenantQueryScopingError < StandardError; end

  NULL_TENANT_QUERY_SCOPING_IGNORED_PATHS = Regexp.union([
    %r{packages/external_identities/app/models/user/multi_tenant_enterprise_managed_dependency.rb},
    %r{packages/users/app/models/user.rb},
    %r{vendor/},
  ])
  NULL_TENANT_QUERY_SCOPING_BACKTRACE_CLEANER = ActiveSupport::BacktraceCleaner.new.tap do |cleaner|
    cleaner.add_silencer { |line| line.match?(NULL_TENANT_QUERY_SCOPING_IGNORED_PATHS) }
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  # business_id is currently only used in Proxima
  def validate_multi_tenant_business_id?
    GitHub.multi_tenant_business_id?
  end

  # This method is used to return the correct login value for API serialization for Proxima.
  # Internal calls to the API return the unique login value,
  # non-internal calls return the display_login value.
  #
  # For non-proxima environments always returns user.display_login which is the same value as user.login.
  #
  # Do not use this method unless specifically indicated.
  # Other options to use: `user.login`, `user.display_login`
  def login_for_api(use: :default)
    return display_login unless GitHub.multi_tenant_enterprise?

    # TODO: Update to throw on unknown `use` values.
    # https://github.com/github/github/pull/261256/files/7403b0ac9ceeab75ee0e5b1393575f18510a8c57#r1123242822
    GitHub.dogstats.increment("repository.login_for_api",  tags: ["use:#{use}"])

    case use
    when :unique
      login
    when :display
      display_login
    else
      if !GitHub.proxima_internal_api_unique_logins_required?
        display_login
      else
        login
      end
    end
  end

  # This method is used to return the correct tenant slug when creating avatar URL tokens for Proxima.
  def tenant_slug_for_avatar
    return "" unless GitHub.multi_tenant_enterprise?
    tenant = nil
    if organization? && self.feature_flag_enabled_or_raise?(:proxima_avatar_tenant_slug_fix) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      # If the organization user doesn't have a business id, or the business id is zero, treat the user as a system account
      tenant = async_business.sync if defined?(business_id) && business_id && !business_id.zero?
    else
      tenant = enterprise_managed_business
    end
    return GitHub.company_specific_entity_acronym unless tenant
    tenant.slug
  end

  module ClassMethods

    def scope_to_current_tenant
      tenant_id = GitHub::CurrentTenant.get.try(:id) || NON_ENTERPRISE_MANAGED_BUSINESS_ID
      scope = where(business_id: tenant_id)

      if tenant_id != NON_ENTERPRISE_MANAGED_BUSINESS_ID
        # include scope for global application actors like the Actions bot or trusted OAuth app owner
        scope = scope.or(where(business_id: NON_ENTERPRISE_MANAGED_BUSINESS_ID))
      end

      instrument_tenant_query_scoping if GitHub::CurrentTenant.get.nil?

      scope
    end

    def instrument_tenant_query_scoping
      return unless GitHub.multi_tenant_enterprise?

      GitHub.dogstats.increment("tenant_context.query_scoping", tags: GitHub::CurrentTenant.metrics_tags)
    end

  end
end
