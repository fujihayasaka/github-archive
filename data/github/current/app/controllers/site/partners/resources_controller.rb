# typed: true
# frozen_string_literal: true

class Site::Partners::ResourcesController < Site::BaseController
  include Site::BreadcrumbDependency
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  # Legacy implementation constants
  INDEX_VIEW     = "site/partners/resources/index"
  SHOW_VIEW_PATH = "site/partners/integration_resources"

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    if FeatureFlag.vexi.enabled?(:contentful_lp_partners, nil, default: false)
      "resources"
    else
      "technology-partners"
    end
  end

  CSP_EXCEPTIONS = T.let({
    connect_src: [GitHub.marketing_forms_api_host_url],
    frame_src: [GitHub.urls.octocaptcha_host_name, "https://www.youtube-nocookie.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze, T::Hash[T.untyped, T.untyped])

  stylesheet_bundle "resources"

  around_action :switch_locale

  include GitHub::Memoizer

  before_action :add_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions
  before_action :allow_initial_cookie_consent
  before_action :enable_microsoft_analytics
  before_action :add_microsoft_analytics_csp_exceptions

  def index
    legacy_index and return if use_legacy?

    page_params = {
      path: "/partners/resources",
      locale: user_locale,
      url: request.url,
      query: request.query_parameters,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::Core::Pages::IndexPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing? || hidden?(page)

    render_react_app(
      payload: {
        contentfulRawJsonResponse: page.refined_view_data,
        userLoggedIn: logged_in?,
        additionalProps: {
          filters: page.grouped_filters,
          totalPages: page.total_pages,
          sortOptions: page.sort_options_with_values,
          currentSort: page.current_sort_value,
          showSpotlightCard: page.show_spotlight_card,
        },
      },
      title: page.title,
      page_data: page.options,
    )
  end

  def show
    legacy_show and return if use_legacy?

    page_params = {
      path: "/partners/resources/#{params[:id]}",
      locale: user_locale,
      url: request.url,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::ContainerPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing? || hidden?(page)

    add_breadcrumb "Resources", "/partners/resources"
    add_breadcrumb page.title, "/partners/resources/#{params[:id]}"

    react_render_params = {
      app_payload_generator: page.has_form? ? app_payload_generator : nil,
      payload: {
        contentfulRawJsonResponse: page.view_data,
        userLoggedIn: logged_in?,
        breadcrumbLinks: breadcrumbs,
        indexPath: "/partners/resources",
      },
      title: page.title,
      page_data: { **page.options },
    }.compact

    render_react_app(**react_render_params)
  end

  private

  # Please do not copy or replicate this code. We're disabling linting rule to allow dynamic template rendering for the TPE site migration. We have consulted the marketing-engineering team and we have been instructed to do so. You can read more about the project at this issue https://github.com/github/technology-partnerships-and-engineering/issues/3189
  def legacy_index
    self.class.layout "site"
    self.class.javascript_bundle "technology-partners"

    page_title        = "Resources"
    hero_text         = <<~EOS
      We hope you find this curated list of resources helpful. Every effort
      for accuracy has been made, but the fast pace of business and technology
      can make links and references outdated.
    EOS

    resource_files    = Dir.glob(Rails.root.join("app", "views", SHOW_VIEW_PATH, "*.html.erb"))
    posts             = []
    all_categories    = []
    category_tags_map = {}

    resource_files.each do |file|
      content        = File.read(file) rescue ""
      title_match    = content.match(/post_title\s*=\s*['"](.+?)['"]/)
      categories     = extract_array(content, /post_categories\s*=\s*\[(.*?)\]/m)
      tags           = extract_array(content, /post_tags\s*=\s*\[(.*?)\]/m)
      priority_match = content.match(/post_priority\s*=\s*(\d+)/)
      sections       = extract_array(content, /post_sections\s*=\s*\[(.*?)\]/m)
      type_match     = content.match(/post_type\s*=\s*['"](.+?)['"]/)
      preview_match  = content.match(/post_preview\s*=\s*['"](.+?)['"]/)

      all_categories.concat(categories)
      categories.each do |cat|
        category_tags_map[cat] ||= []
        category_tags_map[cat].concat(tags)
      end

      posts << {
        title:      (title_match ? title_match[1] : File.basename(file, ".html.erb").titleize),
        categories: categories,
        tags:       tags,
        priority:   (priority_match ? priority_match[1].to_i : 999),
        sections:   sections,
        type:       (type_match ? type_match[1] : nil),
        preview:    (preview_match ? preview_match[1] : nil),
        slug:       File.basename(file, ".html.erb"),
        file_path:  file
      }
    end

    categories = all_categories.uniq.sort
    category_tags_map.each { |k, v| category_tags_map[k] = v.uniq.sort }

    render INDEX_VIEW,
      locals: {
        page_title:        page_title,
        hero_text:         hero_text,
        posts:             posts,
        categories:        categories,
        category_tags_map: category_tags_map
      }
  end

  # rubocop:disable GitHub/RailsControllerRenderLiteral
  def legacy_show
    template = "#{SHOW_VIEW_PATH}/#{params[:id]}"

    if lookup_context.find_all(template).any?
      render template: template
    else
      render_404
    end
  end

  def use_legacy?
    !FeatureFlag.vexi.enabled?(:contentful_lp_partners, current_user, default: false)
  end

  def extract_array(content, regexp)
    if (m = content.match(regexp))
      m[1].scan(/['"]([^'"]+)['"]/).flatten
    else
      []
    end
  end

  def hidden?(page)
    return true unless FeatureFlag.vexi.enabled?(:contentful_lp_partners, current_user, default: false)
    return false if page.feature_flag.blank?

    !FeatureFlag.vexi.enabled?(page.feature_flag, current_user, default: false)
  end

  def app_payload_generator
    lambda do
      {
        octocaptchaHost: GitHub.urls.octocaptcha_host_name,
        marketingFormsApiHost: GitHub.marketing_forms_api_host_url,
        marketingTargetedCountries: marketing_targeted_countries
      }
    end
  end

  memoize def marketing_targeted_countries
    ::TradeControls::Countries.marketing_targeted_countries.map { |name, alpha, *_| { name: name, alpha: alpha } }
  end
end
