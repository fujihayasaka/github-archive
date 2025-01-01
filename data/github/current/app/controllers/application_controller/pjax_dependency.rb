# typed: true
# frozen_string_literal: true

module ApplicationController::PjaxDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :pjax_version, :pjax_csp_version, :pjax_css_version, :pjax_js_version
    helper_method :pjax?
    helper_method :pjax_request_wants_repo_content_container?
  end

  # PJAX Asset Version.
  #
  # The client receives the initial version in the first requests
  # layout. Addition PJAX requests return the value in the
  # X-PJAX-Version response header. Any change in the version will
  # cause the pjax request to do a full load of the next page.
  #
  # Returns a SHA256 hex String.
  def pjax_version
    @pjax_version ||= compute_pjax_version
  end

  def pjax_csp_version
    @pjax_csp_version ||= compute_pjax_csp_version
  end

  def pjax_css_version
    @pjax_css_version ||= compute_pjax_css_version
  end

  def pjax_js_version
    @pjax_js_version ||= compute_pjax_js_version
  end

  def compute_pjax_version
    csp_policy_str = SecureHeaders.config_for(request).generate_headers["content-security-policy"]

    assets = AssetBundlesHelper.new(current_user)
    parts = [
      "5",
      csp_policy_str,
      *[
        "primer.css",
        "global.css",
        "github.css",
        *assets.required_bundles
      ].map do |bundle|
        assets.expand_bundle_name(bundle)
      end,
    ].compact
    Digest::SHA256.hexdigest(parts.join(":"))
  end

  def compute_pjax_csp_version
    csp_policy_str = SecureHeaders.config_for(request).generate_headers["content-security-policy"]
    Digest::SHA256.hexdigest(csp_policy_str)
  end

  def compute_pjax_css_version
    assets = AssetBundlesHelper.new(current_user)
    parts = [
     *[
       "primer.css",
       "global.css",
       "github.css",
      ].map do |bundle|
        assets.expand_bundle_name(bundle)
      end,
    ].compact
    Digest::SHA256.hexdigest(parts.join(":"))
  end

  def compute_pjax_js_version
    assets = AssetBundlesHelper.new(current_user)
    parts = [
      *assets.required_bundles.map do |bundle|
        assets.expand_bundle_name(bundle)
      end
    ].compact
    Digest::SHA256.hexdigest(parts.join(":"))
  end

  # Enforces the the `frame_navigation` layout for requests that don't require the full
  # `application` layout. This makes responses smaller and faster, since we skip rendering
  # a bunch of stuff that won't be used. Both PJAX and Turbo-Frames requests will benefit
  # from this hack.
  # HACK: this is horrible and @github/josh can tell you why.
  def _layout_for_option(name)
    if name == :default && (pjax? || turbo_frame_request?)
      "layouts/frame_navigation"
    else
      super
    end
  end

  # Always set Vary: X-PJAX, X-PJAX-Container
  #
  # Ensures PJAX requests are always cached seperately from their full response
  # counterparts.
  def set_vary_pjax
    add_headers_to_vary(%w(X-PJAX X-PJAX-Container))
  end

  def instrument_pjax_version_change(pjax:, csp:, css:, js:, headers_present:)
    # will only increment datadog stats when pjax version change happens
    return unless pjax

    # add tags for pjax, csp, css, js changes
    tags = [
      "pjax:#{pjax}",
      "csp:#{csp}",
      "css:#{css}",
      "js:#{js}",
      "headers_present:#{headers_present}"
    ]

    # add tags for referring routes controllers and actions
    referring_route = github_internal_referrer_route
    if referring_route.present?
      tags += ["referer_controller:#{referring_route[:controller]}", "referer_action:#{referring_route[:action]}"]
    end

    tags += ["request_controller:#{params[:controller]}"] unless params[:controller].nil?
    tags += ["request_action:#{params[:action]}"] unless params[:action].nil?

    GitHub.dogstats.increment("pjax_version_change", tags: tags)
  end

  # Automatically the X-PJAX-Version on all PJAX responses.
  def set_pjax_version
    if pjax?
      pjax_header = request.headers["X-PJAX-Version"]
      csp_header = request.headers["X-PJAX-CSP-Version"]
      css_header = request.headers["X-PJAX-CSS-Version"]
      js_header = request.headers["X-PJAX-JS-Version"]
      instrument_pjax_version_change(
        pjax: pjax_version != pjax_header,
        csp: pjax_csp_version != csp_header,
        css: pjax_css_version != css_header,
        js: pjax_js_version != js_header,
        headers_present:  csp_header.present? && css_header.present? && js_header.present?  # we want to make sure the stats we get is accurate
      )

      response.headers["X-PJAX-VERSION"] = pjax_version
    end
  end

  # Set the request url as a response header to pjax. Yes, this sounds dumb
  # but XHR can't figure out which request url a response came from after it
  # follows a redirect.
  def set_pjax_url
    if pjax?
      response.headers["X-PJAX-URL"] = request.url
    end
  end

  # Determines whether a request was made via pjax.
  # Can be used in views.
  #
  # Returns a boolean.
  def pjax?
    request.headers["X-PJAX"] == "true"
  end

  def pjax_container
    return @pjax_container if defined? @pjax_container

    @pjax_container = request.headers["X-PJAX-Container"].presence
  end

  def repo_pjax_container?
    ["#js-repo-pjax-container", "#repo-content-pjax-container"].include?(pjax_container)
  end

  # Is this a PJAX request that will replace content into the
  # `#repo-content-pjax-container` element?
  #
  # Returns a Boolean.
  def pjax_request_wants_repo_content_container?
    return @pjax_request_wants_repo_content_container if defined? @pjax_request_wants_repo_content_container

    @pjax_request_wants_repo_content_container = pjax? && pjax_container == "#repo-content-pjax-container"
  end

  # Detect cross-repo pjax redirects and rewrite them to make sure that they
  # trigger a hard refresh in browsers, therefore skipping pjax.
  def sanitize_pjax_redirects
    if 302 == response.response_code && repo_pjax_container?
      # extract "name/owner" pairs from origin/destination URLs
      name_owner_pairs = [request.url, response.location].map { |u| u.to_s.split("/")[3..4].join("/").downcase }
      unless name_owner_pairs.inject(:==)
        response.status = 200
        response.body = ""
        response.headers["X-PJAX-URL"] = response.location
      end
    end
  end
end
