# typed: true
# frozen_string_literal: true

class Site::NewsroomController < Site::BaseController
  include ReactHelper

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
  }.freeze

  stylesheet_bundle "newsroom"

  def self.react_bundle_name
    "newsroom"
  end

  def index
    render_404 and return unless newsroom_templates_enabled?
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Newsroom::Pages::HomePage)

    view_data = Site::Contentful::Marketing::Newsroom::Pages::HomePage.new.view_data
    render_page(view_data)
  end

  def show
    render_404 and return unless newsroom_templates_enabled?
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Newsroom::Pages::ShowPage, slug: params[:slug])

    view_data = Site::Contentful::Marketing::Newsroom::Pages::ShowPage.new(slug: params[:slug]).view_data
    render_page(view_data)
  end

  private

  def render_page(view_data)
    render_404 and return if view_data.nil? || hidden?(view_data)

    render_react_app(
      payload: { contentfulRawJsonResponse: view_data[:contentful_raw_json_response], userLoggedIn: logged_in? },
      title: view_data[:title],
      page_data: page_options(view_data),
      ssr: true
    )
  end

  def page_options(view_data)
    {
      **dark_mode_opts(view_data),
      **seo_opts(view_data),
      **global_navbar_opts(view_data),
    }
  end

  def dark_mode_opts(view_data)
    view_data.fetch(:use_dark_mode, false) ? { class: "header-dark", marketing_footer_theme: "dark" } : {}
  end

  def seo_opts(view_data)
    {
      description: view_data[:seo].try(:dig, :description),
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

  def hidden?(view_data)
    feature_flag = view_data.fetch(:feature_flag, nil)

    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !feature_enabled_globally_or_for_current_user?(feature_flag)
  end

  def newsroom_templates_enabled?
    feature_enabled_globally_or_for_current_user?(:contentful_lp_newsroom)
  end
end
