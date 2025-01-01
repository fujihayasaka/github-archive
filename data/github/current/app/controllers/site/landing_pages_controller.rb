# typed: true
# frozen_string_literal: true

class Site::LandingPagesController < Site::BaseController
  include ReactHelper
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  before_action :add_csp_exceptions

  before_action :allow_initial_cookie_consent, only: [:show], if: :tracking_allowed_for_path?
  before_action :enable_microsoft_analytics, only: [:show], if: :tracking_allowed_for_path?
  before_action :add_microsoft_analytics_csp_exceptions, only: [:show], if: :tracking_allowed_for_path?

  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  before_action :load_page_specific_stylesheet

  CSP_EXCEPTIONS = {
    connect_src: [GitHub.marketing_forms_api_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
  }.freeze

  stylesheet_bundle "landing-pages"

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, slug: request&.path)

    page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: request&.path).view_data

    render_404 and return if page_data.nil? || hidden?(page_data)

    global_navbar_opts = get_global_navbar_opts(page_data)
    dark_mode_opts = get_dark_mode_opts(page_data)
    seo_opts = get_seo_opts(page_data)
    metadata = add_metadata(page_data)

    load_stylesheet_for_template(page_data[:template_name])

    render_react_app(
      app_payload_generator: -> { { octocaptchaHost: GitHub.urls.octocaptcha_host_name, marketingFormsApiHost: GitHub.marketing_forms_api_host_url } },
      payload: { contentfulRawJsonResponse: page_data[:contentful_raw_json_response], userLoggedIn: logged_in?, octocaptchaHost: GitHub.urls.octocaptcha_host_name },
      title: page_data[:title],
      page_data: {}.merge(global_navbar_opts).merge(dark_mode_opts).merge(seo_opts).merge(metadata),
      ssr: true
    )
  end

  # We use this controller to exercise error handling and exception reporting.
  # The React application will render a component that simply throws an exception.
  def boomtown # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless employee?

    render_react_app(title: "Boomtown!", ssr: true)
  end

  private

  def tracking_allowed_for_path?
    return true if contact_sales_path?

    [security_path].include?(T.must(request).path)
  end

  def contact_sales_path?
    [enterprise_contact_path, enterprise_contact_thanks_path].include?(T.must(request).path)
  end

  def hidden?(show_page_data)
    feature_flag = show_page_data.fetch(:feature_flag, nil)

    return false if feature_flag.nil?

    !feature_flag.instance_of?(String) || !feature_enabled_globally_or_for_current_user?(feature_flag)
  end

  def get_global_navbar_opts(show_page_data)
    case show_page_data.fetch(:global_navbar_style, nil)
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

  def add_metadata(show_page_data)
    {
      revenue_play: show_page_data.fetch(:revenue_play, nil),
      octolytics_page_type: "marketing"
    }
  end

  def get_dark_mode_opts(show_page_data)
    show_page_data.fetch(:use_dark_mode, false) ? { class: "header-dark", marketing_footer_theme: "dark" } : {}
  end

  def get_seo_opts(show_page_data)
    {
      richweb: {
        description: show_page_data[:seo].try(:dig, :description),
        image: show_page_data[:seo].try(:dig, :social_media_image),
        title: show_page_data[:title],
        url: T.must(request).original_url
      }
    }
  end

  def load_page_specific_stylesheet
    self.stylesheet_bundles.add(:"about-diversity") if T.must(request).path == about_diversity_path
    self.stylesheet_bundles.add(:"contact-sales") if contact_sales_path?
    self.stylesheet_bundles.add(:"feature-preview") if T.must(request).path == features_preview_path
  end

  def load_stylesheet_for_template(template)
    self.stylesheet_bundles.add(:"landing-pages-template-free-form") if template == "templateFreeForm"
    self.stylesheet_bundles.add(:"landing-pages-template-f2") if template == "templateF2"
    self.stylesheet_bundles.add(:"landing-pages-template-universe-23-waitlist") if template == "templateUniverse23Waitlist"
  end
end
