# typed: true
# frozen_string_literal: true

class Site::Resources::WhitepapersController < Site::Resources::BaseController

  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
    img_src: [GitHub.contentful_marketing_image_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
  }.freeze

  stylesheet_bundle "resources"

  def index
    render_404 and return unless lp_whitepapers?
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage)

    page = Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage.new

    render_404 and return if page.view_data.nil? || hidden_page?(page.view_data)

    page.filter_hidden_pages { |ff| hidden_content?(ff) }
    page.sort_by_published_date

    render_react_app(
      payload: { contentfulRawJsonResponse: page.view_data[:contentful_raw_json_response], userLoggedIn: logged_in? },
      title: page.view_data[:title],
      page_data: page_options(page.view_data),
      ssr: true
    )
  end

  def show
    render_404 and return unless lp_whitepapers?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage, slug: params[:resource])

    view_data = Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage.new(slug: params[:resource]).view_data
    render_page(view_data)
  end

  def confirmation # rubocop:disable GitHub/UseRestfulActions, GitHub/UseRestfulActions
    render_404 and return unless lp_whitepapers?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage, slug: params[:resource])

    view_data = Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage.new(slug: params[:resource]).view_data
    render_page(view_data)
  end

  private

  def render_page(view_data)
    render_404 and return if view_data.nil? || hidden_page?(view_data)

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
      **add_metadata(view_data),
    }
  end

  def dark_mode_opts(view_data)
    view_data.fetch(:use_dark_mode, false) ? { class: "header-dark", marketing_footer_theme: "dark" } : {}
  end

  def add_metadata(view_data)
    {
      revenue_play: view_data.fetch(:revenue_play, nil),
      octolytics_page_type: "marketing"
    }
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

  def hidden_page?(view_data)
    feature_flag = view_data.fetch(:feature_flag, nil)

    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !feature_enabled_globally_or_for_current_user?(feature_flag)
  end

  def hidden_content?(feature_flag)
    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !feature_enabled_globally_or_for_current_user?(feature_flag)
  end

  def lp_whitepapers?
    feature_enabled_globally_or_for_current_user?(:contentful_lp_whitepapers)
  end


end
