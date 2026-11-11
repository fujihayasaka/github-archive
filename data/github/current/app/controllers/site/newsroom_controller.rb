# typed: true
# frozen_string_literal: true

class Site::NewsroomController < Site::BaseController

  before_action :add_csp_exceptions
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube-nocookie.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze

  stylesheet_bundle "newsroom"

  def self.react_bundle_name
    "newsroom"
  end

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Newsroom::Pages::HomePage)

    view_data = Site::Contentful::Marketing::Newsroom::Pages::HomePage.new.view_data
    render_page(view_data)
  end

  def category # rubocop:disable GitHub/UseRestfulActions
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Newsroom::Pages::CategoryPage, page: params[:page])

    page = Site::Contentful::Marketing::Newsroom::Pages::CategoryPage.new(page: params[:page])

    render_404 and return if page.view_data.blank? || hidden_page?(page.view_data)

    page.filter_hidden_pages! { |ff| hidden_content?(ff) }
    page.apply_pagination!

    render_404 and return if page.page_number < 1 || page.page_number > page.total_pages

    render_react_app(
      payload: { contentfulRawJsonResponse: page.view_data[:contentful_raw_json_response], userLoggedIn: logged_in?, additionalProps: { page: page.page_number, totalPages: page.total_pages } },
      title: page.view_data[:title],
      page_data: page_options(page.view_data),
    )
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Newsroom::Pages::ShowPage, slug: params[:slug])

    view_data = Site::Contentful::Marketing::Newsroom::Pages::ShowPage.new(slug: params[:slug]).view_data
    render_page(view_data)
  end

  private

  def render_page(view_data)
    render_404 and return if view_data.blank? || hidden_page?(view_data)

    render_react_app(
      payload: { contentfulRawJsonResponse: view_data[:contentful_raw_json_response], userLoggedIn: logged_in? },
      title: view_data[:title],
      page_data: page_options(view_data),
    )
  end

  def page_options(view_data)
    {
      **dark_mode_opts(view_data),
      **seo_opts(view_data),
      **global_navbar_opts(view_data),
      **add_metadata(view_data),
    }
  end

  def dark_mode_opts(view_data)
    view_data.fetch(:use_dark_mode, false) ? { class: "header-dark", marketing_footer_theme: "dark" } : {}
  end

  def add_metadata(view_data)
    {
      revenue_play: view_data.fetch(:revenue_play, nil),
    }
  end

  def seo_opts(view_data)
    {
      description: view_data[:seo].try(:dig, :description),
      noindex_and_nofollow: view_data[:seo].try(:dig, :noindex_and_nofollow),
      richweb: {
        description: view_data[:seo].try(:dig, :description),
        image: view_data[:seo].try(:dig, :social_media_image),
        title: view_data[:title],
        url: T.must(request).original_url
      }
    }
  end

  def global_navbar_opts(view_data)
    case view_data.fetch(:global_navbar_style, nil)
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

  def hidden_page?(view_data)
    feature_flag = view_data.fetch(:feature_flag, nil)

    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !FeatureFlag.vexi.enabled_or_raise?(feature_flag, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def hidden_content?(feature_flag)
    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !FeatureFlag.vexi.enabled_or_raise?(feature_flag, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end
end
