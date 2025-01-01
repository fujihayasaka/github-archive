# typed: true
# frozen_string_literal: true
#
# Enabling GitHub Connect's private search on an enterprise (aka business)
# requires the connect app to be installed in all of the enterprise's
# organizations, so a search will find the organizations' private assets.
#
# This job ensures that, for each GHES instance connected to an enterprise, the
# app is present in all orgs if private search is enabled (and only on those),
# and removed from all orgs otherwise.
#
# It only applies the missing operations, in order to be safe to trigger
# whenever the private search (or any feature) is flipped on the enterprise,
# when an organization is added/removed, etc.
#
# In the future (if we find that this approach has performance/load
# implications), we might accept an extra organization_id or an extra
# integration_id (but not both), and limit the processing to that organization
# or integration.

class UpdatePrivateSearchOnEnterpriseOrgsJob < ApplicationJob
  queue_as :github_connect

  class AppInstallError < RuntimeError; end
  class AppUninstallError < RuntimeError; end

  resolve_tenant_context do |business_id|
    Business.find_by(id: business_id)
  end

  # Ensure we only run one job per Enterprise at a time, but don't lose any
  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10
  def perform(business_id, options = {})
    lock_key = "update-private-search-on-enterprise-#{business_id}"
    concurrent_jobs = 1
    lock_ttl = 1.hour
    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
      perform!(business_id, options)
    end
  end

  def perform!(business_id, options = {})
    entry_point = options[:entry_point]
    business = Business.find_by(id: business_id)
    return unless business.present?

    connect_apps = T.must(business).enterprise_installations.map(&:github_app).compact

    connect_apps.each do |connect_app|
      if private_search_enabled?(connect_app)
        install_in_business_orgs(connect_app, business, entry_point)
        remove_from_non_business_orgs(connect_app, business)
      else
        remove_from_any_orgs(connect_app)
      end
    end
  end

  private

  def private_search_enabled?(connect_app)
    # Private search is the only feature that requires repository-type default
    # permissions (which is, indirectly, why it requires the org installs)
    connect_app.latest_version.any_permissions_of_type?(Repository)
  end

  def install_in_business_orgs(connect_app, business, entry_point)
    business.organizations.each do |org|
      install(connect_app, org, entry_point)
    end
  end

  def remove_from_non_business_orgs(connect_app, business)
    (orgs_with_app_installed(connect_app) - business.organizations).each do |org|
      uninstall(connect_app, org)
    end
  end

  def remove_from_any_orgs(connect_app)
    orgs_with_app_installed(connect_app).each do |org|
      uninstall(connect_app, org)
    end
  end

  def orgs_with_app_installed(connect_app)
    connect_app.installations.map(&:target).select do |target|
      target.is_a?(Organization)
    end
  end

  def install(connect_app, org, entry_point)
    return if connect_app.installed_on?(org)

    with_write do
      result = connect_app.install_on(org, installer: org.admins.first, repositories: [], entry_point: entry_point)
      raise(AppInstallError, result.error) unless result.success?
    end
  end

  def uninstall(connect_app, org)
    return unless connect_app.installed_on?(org)

    with_write do
      result = connect_app.installations_on(org).destroy_all
      raise(AppUninstallError) unless result
    end
  end
end
