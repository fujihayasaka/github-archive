# typed: true
# frozen_string_literal: true

module Signups
  module CustomContentDependency

    CONTENTFUL_SIGNUP_SLUG = "/signup"
    QUERY_PARAM_LIMIT = 50

    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
    end

    sig { params(custom_page_param: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def contentful_custom_content_entry(custom_page_param = nil)
      return nil if !custom_page_param

      custom_page_param_downcased = custom_page_param.downcase

      ContentfulCustomContent.new(retrieve_signup_contentful_data, custom_page_param_downcased).to_h
    end

    sig { returns(T.nilable(String)) }
    def custom_page_param
      return params[:with].to_s[0...QUERY_PARAM_LIMIT].strip if params[:with].present?
      params[:get_started_with].present? ? params[:get_started_with].to_s[0...QUERY_PARAM_LIMIT].strip : nil
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
  end
end
