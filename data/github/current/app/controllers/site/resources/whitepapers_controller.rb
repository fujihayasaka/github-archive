# typed: true
# frozen_string_literal: true

class Site::Resources::WhitepapersController < Site::Resources::BaseController
  around_action :switch_locale, only: [:index, :show, :confirmation]

  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = {
    connect_src: [GitHub.marketing_forms_api_host_url],
    frame_src: [GitHub.urls.octocaptcha_host_name, "https://www.youtube-nocookie.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze

  stylesheet_bundle "resources"

  def index
    options = {
      page: params[:page],
      content_type: params[:contentTypes],
      topics: params[:topics],
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage, **options)

    page = Site::Contentful::Marketing::Resources::Pages::Whitepapers::IndexPage.new(**options)

    render_404 and return if page.view_data.blank? || hidden_page?(page.view_data)

    page.filter_hidden_pages! { |ff| hidden_content?(ff) }
    page.apply_filters!
    page.apply_pagination!

    render_404 and return if page.page_number < 1 || page.page_number > page.total_pages

    render_react_app(
      payload: {
        contentfulRawJsonResponse: page.view_data[:contentful_raw_json_response],
         userLoggedIn: logged_in?,
         additionalProps: {
          page: page.page_number,
          totalPages: page.total_pages,
          filters: {
            contentTypes: page.content_types,
            topics: page.topics
          },
         }
      },
      title: page.view_data[:title],
      page_data: page_options(page.view_data),
    )
  end

  def show
    options = {
      slug: params[:resource],
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage, **options)

    view_data = Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage.new(**options).view_data
    render_page(view_data)
  end

  def confirmation # rubocop:disable GitHub/UseRestfulActions, GitHub/UseRestfulActions
    options = {
      slug: params[:resource],
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage, **options)

    view_data = Site::Contentful::Marketing::Resources::Pages::Whitepapers::ShowPage.new(**options).view_data

    render_404 and return if view_data.blank? || hidden_page?(view_data)

    render_react_app(
      payload: { contentfulRawJsonResponse: view_data[:contentful_raw_json_response], userLoggedIn: logged_in? },
      title: view_data[:title],
      page_data: { **page_options(view_data), noindex_and_nofollow: true },
    )
  end

  private

  def render_page(view_data)
    render_404 and return if view_data.blank? || hidden_page?(view_data)

    render_react_app(
      app_payload_generator: -> {
        {
          octocaptchaHost: GitHub.urls.octocaptcha_host_name,
          marketingFormsApiHost: GitHub.marketing_forms_api_host_url,
          marketingTargetedCountries: marketing_targeted_countries,
          locale: user_locale || I18n.locale
        }
      },
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
