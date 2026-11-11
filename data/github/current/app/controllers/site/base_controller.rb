# typed: true
# frozen_string_literal: true

class Site::BaseController < ApplicationController
  include AnalyticsHelper
  include Site::MicrosoftAnalyticsDependency
  include Site::VendorImagePixelDependency
  include LocalizationDependency

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :disable_in_enterprise_and_proxima
  before_action :disable_color_modes
  before_action :disable_header_redesign

  layout "site"

  javascript_bundle "marketing"
  stylesheet_bundle "site"

  private

  def disable_in_enterprise_and_proxima
    render_404 if GitHub.single_or_multi_tenant_enterprise?
  end

  def fetch_contentful_preview?
    return false unless FeatureFlag.vexi.enabled?(:site_contentful_previews, current_user, default: false)
    return false unless params[:preview].present?
    return false unless current_user&.employee?

    @contentful_preview = params[:preview] == "true"
  end

  def fetch_contentful_page_data(page_class: Site::Contentful::Marketing::LandingPages::Pages::ShowPage)
    options = {
      slug: request&.path,
      preview: fetch_contentful_preview?
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(page_class, **options) unless fetch_contentful_preview?

    page_class.new(**options).view_data
  end

  def landing_page_hidden?(page_data)
    feature_flag = page_data.fetch(:feature_flag, nil)
    return false if feature_flag.nil?

    !FeatureFlag.vexi.enabled?(feature_flag, current_user, default: false)
  end

  def render_react_landing_page(page_data:, page_data_overrides: {}, payload: {}, path_override: nil)
    theme = page_data[:use_dark_mode] ? "dark" : "light"

    default_page_data = {
      marketing_page_theme: theme,
      marketing_footer_theme: theme,
      description: page_data[:seo].try(:dig, :description),
      revenue_play: page_data[:revenue_play],
      richweb: {
        description: page_data[:seo].try(:dig, :description),
        image: page_data[:seo].try(:dig, :social_media_image),
        title: page_data[:title],
        url: T.must(request).original_url,
      },
    }

    default_payload = {
      contentfulRawJsonResponse: page_data[:contentful_raw_json_response],
      isLoggedIn: logged_in?,
    }

    render_react_app(
      app_name: "landing-pages",
      title: page_data[:title],
      page_data: default_page_data.merge(page_data_overrides),
      payload: default_payload.merge(payload),
      path_override: path_override,
      custom_tags: ["controller:#{controller_path}", "action:#{action_name}"],
    )
  end
end
