# typed: strict
# frozen_string_literal: true

class Site::Resources::TypesController < Site::Resources::BaseController
  include Site::BreadcrumbDependency
  around_action :switch_locale, only: [:show]
  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Mysql5, optional: true

  sig { returns(T.nilable(String)) }
  def self.react_bundle_name
    "resources"
  end

  CSP_EXCEPTIONS = T.let({
    connect_src: [GitHub.marketing_forms_api_host_url],
    frame_src: ["https://www.youtube-nocookie.com", GitHub.urls.octocaptcha_host_name, "https://play.vidyard.com"],
    img_src: [GitHub.contentful_marketing_image_host_url],
    form_action: ["https://s88570519.t.eloqua.com/e/f2"],
    media_src: [GitHub.contentful_marketing_video_host_url],
  }.freeze, T::Hash[Symbol, T::Array[String]])

  stylesheet_bundle "resources"

  sig { void }
  def show
    page_params = {
      path: type_path,
      locale: user_locale,
      url: request.url,
      query: request.query_parameters,
      preview: fetch_contentful_preview?
    }

    page = Site::Contentful::Marketing::Core::Pages::IndexPage.new(**page_params)
    page.async_revalidate

    render_404 and return if page.missing? || hidden?(page)

    if dynamic_resources_enabled?
      filters = page.chosen_concepts_by_scheme

      topic_ids = params[:topic].to_s.split(",").map(&:strip).reject(&:blank?)
      concept_ids = topic_ids

      limit = [params[:limit]&.to_i || 12, 1].max
      current_page = [params[:page]&.to_i || 1, 1].max
      skip = (current_page - 1) * limit

      resources_query = Site::Contentful::Marketing::GraphQL::TemplateResourceDetails.new(locale: user_locale, resource_type: resource_type)
      resources_data = resources_query.resources_by_concept(concept_ids: concept_ids, limit: limit, skip: skip)
      total_pages = (resources_data[:total].to_f / limit).ceil

      RevalidatePageJob.perform_later(Site::Contentful::Marketing::GraphQL::TemplateResourceDetails, locale: user_locale, resource_type: resource_type, concept_ids: concept_ids, limit: limit, skip: skip)
      RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Taxonomies::Concepts)
      RevalidatePageJob.perform_later(Site::Contentful::Marketing::Resources::Taxonomies::ConceptSchemes)

      render_react_app(
        payload: {
          contentfulRawJsonResponse: page.refined_view_data,
          filters: filters,
          resources: resources_data[:items],
          userLoggedIn: logged_in?,
          additionalProps: {
            selectedFilters: {
              topic: topic_ids,
            },
            totalPages: total_pages,
            sortOptions: page.sort_options_with_values,
            currentSort: page.current_sort_value,
          },
        },
        title: page.title,
        page_data: page.options,
      )
    else
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
  end

  private

  sig { returns(String) }
  def type_path
    resources_type_path(params[:resource_type])
  end

  sig { returns(String) }
  def resource_type
    return "" if params[:resource_type].blank?
    params[:resource_type].singularize.titleize
  end

  sig { params(page: Site::Contentful::Marketing::Core::Pages::IndexPage).returns(T::Boolean) }
  def hidden?(page)
    return false if page.feature_flag.blank?

    !FeatureFlag.vexi.enabled?(page.feature_flag, current_user, default: false)
  end

  sig { returns(T::Boolean) }
  def dynamic_resources_enabled?
    FeatureFlag.vexi.enabled?(:contentful_dynamic_resources, current_user, default: false)
  end
end
