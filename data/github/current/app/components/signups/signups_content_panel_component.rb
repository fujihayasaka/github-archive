# typed: strict
# frozen_string_literal: true

module Signups
  class SignupsContentPanelComponent < ApplicationComponent
    include Signups::Types

    sig { params(custom_page_param: T.nilable(String), contentful_custom_content_entry: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def initialize(custom_page_param: nil, contentful_custom_content_entry: nil)
      @custom_page_param = custom_page_param
      @contentful_custom_content_entry = contentful_custom_content_entry
    end

    private

    sig { returns(T::Boolean) }
    def validate_custom_param
      @custom_page_param.present?
      # Will add more validations via this issue: https://github.com/github/new-user-experience/issues/710
    end

    sig { returns(T::Boolean) }
    def custom_content_enabled?
      validate_custom_param && !!contentful_custom_content_entry && GitHub.flipper[:custom_content_feature].enabled? && is_non_prod_env?
    end

    # Until this feature is ready for production release, allow the feature to be darkshipped via feature flag to review_lab without being released to production.
    # Also allow for this to always be available on localhost.
    sig { returns(T::Boolean) }
    def is_non_prod_env?
      GitHub.host_name.include?("github.localhost") || GitHub.review_lab?
    end

    sig { returns(T.nilable(String)) }
    attr_reader :custom_page_param

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    attr_reader :contentful_custom_content_entry
  end
end
