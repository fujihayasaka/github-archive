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
    rescue StandardError => e
      report_contentful_degradation(e, function: "contentful_custom_content_entry")
      nil
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
    rescue StandardError => e
      # Queue-adapter (Redis/Aurora) failures during enqueue should not break /signup;
      # the page can still render whatever Contentful data is already cached. Site::Contentful
      # network errors aren't expected here (the job only acquires a lock + enqueues), but the
      # broader StandardError rescue keeps the contract simple.
      report_contentful_degradation(e, function: "cache_contentful_data")
    end

    sig { params(error: StandardError, function: String).void }
    def report_contentful_degradation(error, function:)
      message, outcome = case function
      when "cache_contentful_data"
        ["Contentful custom content revalidation enqueue failed; serving cached content", "serve_cached_content"]
      else
        ["Contentful custom content fetch failed; rendering default content", "render_default_content"]
      end
      GitHub.logger.warn(
        message,
        "code.namespace": "Signups::CustomContentDependency",
        "code.function": function,
        "gh.request_id": GitHub.context[:request_id],
        "error.class": error.class.name,
        "error.message": error.message,
      )
      Failbot.report(error, app: "signups", "gh.request_id": GitHub.context[:request_id])
      GitHub.dogstats.increment(
        "signups.new.degraded",
        tags: ["degraded_component:signups_custom_content", "outcome:#{outcome}"],
      )
    end
  end
end
