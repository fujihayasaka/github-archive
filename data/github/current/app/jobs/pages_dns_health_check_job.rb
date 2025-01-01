# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "timeout"

class PagesDnsHealthCheckJob < ApplicationJob
  queue_as :pages_health_check

  attr_reader :page

  def perform(page_id)
    return unless @page = Page.find_by_id(page_id)
    return if !GitHub.pages_custom_cnames? && !page.cname?

    return if Pages::KV.store.exists(page.dns_kv_key).value!

    # Add timeout for DNS health check to prevent indefinite hangs
    checks = nil
    begin
      Timeout.timeout(60) do # 60 second timeout for DNS operations
        checks = page.cname_health_check(page.cname)
      end
    rescue Timeout::Error => e
      GitHub.logger.error("DNS health check timed out",
        page_id: page.id,
        cname: page.cname,
        error: e.message)
      GitHub.dogstats.increment("pages.dns_health_check.dns_timeout")
      return
    end

    # Get default host name for error messages
    page_url_default = page.url.async_default_host_name.sync

    checks_json = {
      domain: checks[:domain].to_h,
      alt_domain: checks[:alt_domain].to_h,
    }
    checks_json.each do |key, check|
      unless check[:valid?]
        checks_json[key][:reason] = PagesDnsHealthCheckJob.format_error_message(check[:reason], check[:apex_domain?], page_url_default)
      end
      if FeatureFlag.vexi.enabled_or_raise?(:pages_wildcard_dns_record_test, page.repository) || FeatureFlag.vexi.enabled_or_raise?(:pages_wildcard_dns_record_test, page.repository.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        checks_json[key][:warning] = PagesDnsHealthCheckJob.format_warning_message(page, checks[key]&.domain&.wildcard_warning)
      end
    end

    with_write { Pages::KV.store.set(page.dns_kv_key, checks_json.to_json, expires: 2.minutes.from_now) }
  end

  def self.format_error_message(error, apex_domain, page_url_default)
    return "" if error.nil?

    return error.to_s unless error.is_a? GitHubPages::HealthCheck::Error

    suggested_record_change = " #{message_variant(apex_domain, page_url_default)}"

    more_info = format_error_more_info(error)

    case error
    when GitHubPages::HealthCheck::Errors::BuildError
      return "Something is wrong with your GitHub Pages site.#{more_info}"
    when GitHubPages::HealthCheck::Errors::DeprecatedIPError
      return "The custom domain for your GitHub Pages site is pointed at an outdated IP address. You must update your site's DNS records if you would like it to be available via your custom domain.#{more_info}"
    when GitHubPages::HealthCheck::Errors::InvalidARecordError
      return "Your site's DNS settings are using a custom subdomain, <code>#{error.domain.host}</code>, that is set up as an <code>A</code> record.#{suggested_record_change}#{more_info}"
    when GitHubPages::HealthCheck::Errors::InvalidAAAARecordError
      return "Your site's DNS settings are using a custom subdomain, <code>#{error.domain.host}</code>, that is set up as an <code>AAAA</code> record.#{suggested_record_change}#{more_info}"
    when GitHubPages::HealthCheck::Errors::InvalidCNAMEError
      return "Your site's DNS settings are using a custom subdomain, <code>#{error.domain.host}</code>, that is not set up with a correct <code>CNAME</code> record.#{suggested_record_change}#{more_info}"
    when GitHubPages::HealthCheck::Errors::InvalidDNSError
      return "Domain's DNS record could not be retrieved.#{more_info}"
    when GitHubPages::HealthCheck::Errors::InvalidDomainError
      return "Domain is not a valid domain.#{more_info}"
    when GitHubPages::HealthCheck::Errors::NotServedByPagesError
      return "Domain does not resolve to the GitHub Pages server.#{more_info}"
    end

    return "#{error.to_s.chomp(".")}.#{more_info}" unless more_info.empty?
    error.to_s
  end

  def self.format_warning_message(page, error)
    case error
    when GitHubPages::HealthCheck::Errors::WildcardRecordError
      # We could elide the warning here, if the page's domain were verified, but domain protection is actually insufficient
      # to protect all the subdomains of a wildcard record; it only protects immediate subdomains, not subdomains an
      # arbitrary number of segments deep. We can only uncomment the following line if domain protection is changed
      # to protect all subdomains.
      # return "" if Page::ProtectedDomain.where(owner: page.owner, name: error.parent_domain, state: :verified).exists?

      # However we can can elide the warning if we know that the page is on our list of blocked domains, because we
      # know that only GitHub own repos can publish pages there.
      cname = Page::CName.new(page, page.cname)
      return "" if cname.blocked_domain? || cname.github_domain?

      return <<~HTML
        The DNS record for your domain appears to be <strong>*.#{error.parent_domain}</strong>, a wildcard record.
        This puts you at risk of domain takeovers, because any GitHub Pages user can serve their content from an
        arbitrary subdomain of #{error.parent_domain}. For more information, see
        <a href="#{GitHub.help_url}#{error.class::DOCUMENTATION_PATH}">Verifying your custom domain for GitHub Pages</a>.
      HTML
    end

    error.to_s
  end

  def self.message_variant(apex_domain, page_url_default)
    if apex_domain
      "We recommend you add an <code>A</code> record pointed to our IP addresses, or an <code>ALIAS</code> record pointing to <code>#{page_url_default}</code>."
    else
      "We recommend you change this to a <code>CNAME</code> record pointing to <code>#{page_url_default}</code>."
    end
  end

  def self.format_error_more_info(error)
    unless error.class::DOCUMENTATION_PATH.blank?
      error_name = error.class.name.split("::").last
      " For more information, see <a href=\"#{GitHub.help_url}#{error.class::DOCUMENTATION_PATH}\">documentation</a> (#{error_name})."
    end
  end
end
