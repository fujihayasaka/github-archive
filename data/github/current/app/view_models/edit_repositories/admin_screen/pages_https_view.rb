# typed: true
# frozen_string_literal: true

class EditRepositories::AdminScreen::PagesHTTPSView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :current_repository
  attr_reader :current_user

  def https_redirect_toggleable?
    page&.https_redirect_toggleable?
  end

  def https_redirect_enabled?
    page&.https_redirect?
  end

  def https_redirect_required?
    page&.https_redirect_required?
  end

  def pages_host_name
    page&.url&.async_host.sync
  end

  def pages_url
    current_repository.gh_pages_url
  end

  def custom_domains_enabled?
    GitHub.pages_custom_cnames?
  end

  def lets_encrypt_enabled?
    GitHub.pages_custom_domain_https_enabled?
  end

  def eligible_for_certificate?
    return @eligible_for_certificate if defined? @eligible_for_certificate
    GitHub::Timer.timeout(3) do
      @eligible_for_certificate = page&.eligible_for_certificate?
    end
  rescue GitHub::Timer::Error
    @eligible_for_certificate = false
  end

  def certificate_issued?
    page&.certificate&.present?
  end

  def certificate_usable?
    page&.certificate&.usable?
  end

  def https_available?
    page&.https_available?
  end

  def help_url
    @help_url ||= DocsUrlConfig.url_for("pages/securing-pages-with-https")
  end

  def https_dns_help_url
    @https_dns_help_url ||= "#{GitHub.help_url}/articles/troubleshooting-custom-domains/#https-errors"
  end

  private

  def page
    @page ||= current_repository.page
  end

end
