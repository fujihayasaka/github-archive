# typed: true
# frozen_string_literal: true

class Site::SolutionsController < Site::BaseController

  before_action :add_csp_exceptions
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_video_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
  }.freeze

  stylesheet_bundle "solutions"

  def self.react_bundle_name
    "solutions"
  end

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Solutions::Pages::OverviewPage)

    page_data = Site::Contentful::Marketing::Solutions::Pages::OverviewPage.new.view_data
    render_page(page_data, { dark_footer: true })
  end

  def category # rubocop:disable GitHub/UseRestfulActions
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Solutions::Pages::CategoryPage, slug: params[:category])

    page_data = Site::Contentful::Marketing::Solutions::Pages::CategoryPage.new(slug: params[:category]).view_data
    render_page(page_data)
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Solutions::Pages::ShowPage, slug: request&.path)

    page_data = Site::Contentful::Marketing::Solutions::Pages::ShowPage.new(slug: request&.path).view_data
    render_page(page_data, { dark_footer: true })
  end

  private

  def render_page(page_data, options = {})
    render_404 and return if page_data.blank? || hidden?(page_data)

    render_react_app(
      payload: { contentfulRawJsonResponse: page_data[:contentful_raw_json_response], userLoggedIn: logged_in? },
      title: page_data[:title],
      page_data: {}.merge(get_dark_mode_opts(page_data, options[:dark_footer])).merge(get_seo_opts(page_data)).merge(get_global_navbar_opts(page_data).merge(add_metadata(page_data))),
    )
  end

  def get_dark_mode_opts(page_data, dark_footer = false)
    if page_data.fetch(:use_dark_mode, false)
      { class: "header-dark", marketing_footer_theme: "dark" }
    else
      { marketing_footer_theme: dark_footer ? "dark" : nil }
    end
  end

  def get_seo_opts(page_data)
    {
      description: page_data[:seo].try(:dig, :description),
      richweb: {
        description: page_data[:seo].try(:dig, :description),
        image: page_data[:seo].try(:dig, :social_media_image),
        title: page_data[:title],
        url: T.must(request).original_url
      }
    }
  end

  def add_metadata(page_data)
    {
      revenue_play: page_data.fetch(:revenue_play, nil),
    }
  end

  def get_global_navbar_opts(page_data)
    case page_data.fetch(:global_navbar_style, nil)
    when "white"
      { class: "header-white" }
    when "light transparent"
      { class: "header-white header-overlay" }
    when "black"
      { class: "header-dark" }
    when "dark transparent"
      { class: "header-overlay" }
    else
      {}
    end
  end

  def hidden?(page_data)
    feature_flag = page_data.fetch(:feature_flag, nil)

    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !feature_enabled_globally_or_for_current_user?(feature_flag)
  end
end
