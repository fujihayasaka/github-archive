# typed: true
# frozen_string_literal: true

require "browser"

module ApplicationController::SecurityHeadersDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }
  extend ActiveSupport::Concern
  include ApplicationController::TurboDependency

  included do
    T.bind(self, T.class_of(ApplicationController))
    after_action :set_html_safe
    helper_method :html_safe_nonce
  end

  private

  # Overrides default CSP with the preview policy if enabled for current_user
  #
  # Returns nothing.
  def set_security_headers
    additions = Hash.new { |h, key| h[key] = [] }

    if preview_features?
      additions[:report_uri] = [GitHub.browser_errors_url]
    end

    if multi_tenant_enterprise?
      SecureHeaders.use_secure_headers_override(request, :multi_tenant_report_only)
    end

    if GitHub::CSP::Policy.dynamic_img_sources.any?
      additions[:img_src] = GitHub::CSP::Policy.dynamic_img_sources
    end

    if GitHub::CSP::Policy.dynamic_connect_src.any?
      additions[:connect_src] = GitHub::CSP::Policy.dynamic_connect_src
    end

    if GitHub.multi_tenant_enterprise?
      memory_alpha_url = GitHub.memory_alpha_url

      additions[:worker_src] = additions[:child_src] = GitHub::CSP::Policy.dynamic_worker_src
      additions[:connect_src] += [GitHub.browser_stats_url, GitHub.browser_errors_url, GitHub.urls.raw_host_name, memory_alpha_url]
      additions[:img_src] += [memory_alpha_url]
      additions[:form_action] += [memory_alpha_url]
      additions[:frame_src] += [Viewscreen.host_url, Notebook.host_url]
      additions[:media_src] += GitHub.video_asset_allowlist
    end

    if additions.any?
      SecureHeaders.append_content_security_policy_directives(request, additions)
    end
  end

  def html_safe_nonce
    csrf_token = Base64.strict_encode64(real_csrf_token(session))
    OpenSSL::Digest::SHA256.hexdigest("html-safe-nonce:#{csrf_token}")
  end

  def set_html_safe
    if (request.xhr? || turbo_frame_request? || turbo_visit_request?) && response.media_type == "text/html" && response_html_safe?
      response.headers["X-HTML-Safe"] = html_safe_nonce
    end
  end

  def response_html_safe?
    response_body&.all?(&:html_safe?)
  end

  # Set Content-Security-Policy header for static files
  #
  # Returns nothing.
  def set_static_file_csp
    SecureHeaders.use_secure_headers_override(request, :static_file_policy)
  end

  # Set Content-Security-Policy header for package registry
  #
  # Returns nothing.
  def set_package_registry_csp
    SecureHeaders.use_secure_headers_override(request, :package_registry_policy)
  end

  # Set Content-Security-Policy header for octocaptcha
  #
  # Returns nothing.
  def set_octocaptcha_csp
    SecureHeaders.use_secure_headers_override(request, :octocaptcha_policy)
  end

  # Set headers telling the browser not to cache this response.
  #
  # Returns nothing.
  def set_cache_control_no_store
    headers["Cache-Control"] = "no-cache, no-store"
  end

  # Clears the browser's cache for browsers supporting the Clear-Site-Data
  # header.
  #
  # Returns nothing.
  def clear_browser_cache
    browser = Browser.new(request.user_agent)
    unless browser.chromium_based?
      SecureHeaders.use_secure_headers_override(request, :clear_browser_cache)
    end
  end

  # Opts out of setting the Referrer-Policy header so that default browser
  # behavior occurs (i.e. referrer is sent if linking from https:/github.com
  # to another HTTPS site but not a HTTP site).
  #
  # Returns nothing.
  def disable_referrer_policy
    SecureHeaders.use_secure_headers_override(
      request, :disable_referrer_policy
    )
  end

  # Switches Referrer-Policy header to same-origin so that user agent does not
  # leak origin hostname when browsing to an external site.
  #
  # Returns nothing.
  def set_same_origin_referrer_policy
    SecureHeaders.use_secure_headers_override(
      request, :same_origin_referrer_policy
    )
  end
end
