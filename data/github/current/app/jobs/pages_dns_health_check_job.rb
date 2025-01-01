# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class PagesDnsHealthCheckJob < ApplicationJob
  queue_as :pages_health_check

  attr_reader :page

  def perform(page_id)
    return unless @page = Page.find_by_id(page_id)
    return if !GitHub.pages_custom_cnames? && !page.cname?

    return if Pages::KV.store.exists(page.dns_kv_key).value!

    checks = page.cname_health_check(page.cname)
    page_url_default = page.url.async_default_host_name.sync

    checks_json = {
      domain: checks[:domain].to_h,
      alt_domain: checks[:alt_domain].to_h,
    }
    checks_json.each do |key, check|
      unless check[:valid?]
        checks_json[key][:reason] = PagesDnsHealthCheckJob.format_error_message(check[:reason], check[:apex_domain?], page_url_default)
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
