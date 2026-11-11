# typed: true
# frozen_string_literal: true

module Site
  module Resources
    class ConfirmationsController < BaseController
      include Site::BreadcrumbDependency
      depends_on_clusters ApplicationRecord::Mysql1,
                          ApplicationRecord::IamAbilities,
                          ApplicationRecord::Collab
      depends_on_clusters ApplicationRecord::Mysql5, optional: true

      CSP_EXCEPTIONS = T.let({
        img_src: [GitHub.contentful_marketing_image_host_url],
      }.freeze, T::Hash[T.untyped, T.untyped])

      sig { returns(T.nilable(String)) }
      def self.react_bundle_name
        "resources"
      end

      stylesheet_bundle "resources"

      def show
        page = Site::Contentful::Marketing::ContainerPage.new(**page_params)
        page.async_revalidate

        redirect_to resource_page_path and return if page.missing? || hidden?(page)

        add_breadcrumb humanized_category, category_page_path
        add_breadcrumb page.title, resource_page_path

        react_render_params = {
          app_payload_generator: page.has_form? ? app_payload_generator : nil,
          payload: {
            contentfulRawJsonResponse: page.view_data,
            userLoggedIn: logged_in?,
            breadcrumbLinks: breadcrumbs,
          },
          title: page.title,
          page_data: { **page.options },
        }.compact

        render_react_app(**react_render_params)
      end

      private

      def page_params
        {
          path: "#{resource_page_path}/confirmation",
          locale: user_locale,
          url: request.url,
        }
      end

      # These paths are constructed manually since we still have bespoke routes for each resource type.
      # Eventually we should migrate to a more generic routing structure.
      def resource_page_path
        "/resources/#{params[:category]}/#{params[:slug]}"
      end

      def category_page_path
        "/resources/#{params[:category]}"
      end

      def humanized_category
        params[:category].gsub("-", " ").humanize
      end

      def hidden?(page)
        return true unless FeatureFlag.vexi.enabled_or_raise?(:contentful_lp_events, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

        if page.feature_flag.present?
          FeatureFlag.vexi.enabled_or_raise?(page.feature_flag.to_s, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        else
          false
        end
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
    end
  end
end
