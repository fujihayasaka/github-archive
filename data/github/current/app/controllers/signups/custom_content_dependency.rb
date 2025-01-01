# typed: true
# frozen_string_literal: true

module Signups
  module CustomContentDependency

    CONTENTFUL_SIGNUP_SLUG = "/signup"

    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
    end

    sig { params(custom_page_param: T.nilable(String)).returns(T.nilable(T::Hash[String, T.untyped])) }
    def contentful_custom_content_entry(custom_page_param = nil)
      return nil if !custom_signup_feature_enabled?
      return nil if !custom_page_param

      ContentfulCustomContent.new(retrieve_signup_contentful_data, custom_page_param).to_h
    end

    private

    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    def retrieve_signup_contentful_data
      cache_contentful_data
      return nil if contentful_pages_data.nil?
      contentful_pages_data[:contentful_raw_json_response]
    end

    def contentful_pages_data
      @contentful_pages_data ||= Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: CONTENTFUL_SIGNUP_SLUG).view_data
    end

    sig { void }
    def cache_contentful_data
      RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, slug: CONTENTFUL_SIGNUP_SLUG)
    end

    sig { returns(T::Boolean) }
    def custom_signup_feature_enabled?
      is_non_prod_env? && GitHub.flipper[:custom_content_feature].enabled?
    end

    # Until this feature is ready for production release, allow the feature to be darkshipped via feature flag to review_lab without being released to production.
    # Also allow for this to always be available on localhost.
    sig { returns(T::Boolean) }
    def is_non_prod_env?
      GitHub.host_name.include?("github.localhost") || GitHub.review_lab?
    end
  end
end
