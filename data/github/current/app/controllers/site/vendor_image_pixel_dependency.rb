# typed: true
# frozen_string_literal: true

module Site::VendorImagePixelDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { ApplicationController }

  include GitHub::Memoizer

  included do
    T.bind(self, T.class_of(ApplicationController))
    helper_method :vendor_pixel_path?
    helper_method :vendor_pixels_enabled?
  end

  private

  sig { returns(T::Boolean) }
  def vendor_pixels_enabled?
    !!(vendor_pixel_path? &&
      !GitHub.single_or_multi_tenant_enterprise? &&
      @cookie_consent_enabled)
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  memoize def enabled_vendor_pixels
    [facebook_pixel, reddit_pixel].compact
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def facebook_pixel
    return unless GitHub.facebook_pixel_id.present?
    host = "www.facebook.com"
    path = "/tr"

    view_event = facebook_pixel_event("PageView")
    click_event = facebook_pixel_event("InitiateCheckout")

    page_view_url = URI::HTTPS.build(host:, path:, query: view_event.to_query)
    click_event_url = URI::HTTPS.build(host:, path:, query: click_event.to_query)

    {
      key: :facebook,
      page_view_url:,
      click_event_url:,
      csp_domains: { img_src: [host] },
    }
  end

  sig { params(event: String).returns(T::Hash[Symbol, T.untyped]) }
  def facebook_pixel_event(event)
    { id: GitHub.facebook_pixel_id, ev: event }
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def reddit_pixel
    return unless GitHub.reddit_pixel_id.present?
    host = "alb.reddit.com"
    path = "/rp.gif"

    view_event = reddit_pixel_event("PageVisit")
    click_event = reddit_pixel_event("Lead")

    if params[:rdt_cid].present?
      rdt_cid = params[:rdt_cid].to_s
      view_event[:click_id] = rdt_cid
      click_event[:click_id] = rdt_cid
    end

    page_view_url = URI::HTTPS.build(host:, path:, query: view_event.to_query)
    click_event_url = URI::HTTPS.build(host:, path:, query: click_event.to_query)

    {
      key: :reddit,
      page_view_url:,
      click_event_url:,
      csp_domains: { img_src: [host] },
    }
  end

  sig { params(event: String).returns(T::Hash[Symbol, T.untyped]) }
  def reddit_pixel_event(event)
    { id: GitHub.reddit_pixel_id, event:, integration: "noscript" }
  end

  sig { returns(T::Boolean) }
  def vendor_pixel_path?
    request.path == "/github-outreach/plan-to-pr"
  end

  sig { void }
  def add_vendor_image_pixel_csp_exceptions
    csp_exceptions = {}

    enabled_vendor_pixels.each do |vendor|
      vendor[:csp_domains].each do |directive, domains|
        csp_exceptions[directive] ||= []
        csp_exceptions[directive].concat(domains)
      end
    end

    SecureHeaders.append_content_security_policy_directives(request, csp_exceptions) if csp_exceptions.any?
  end
end
