# typed: strict
# frozen_string_literal: true

module Signups
  class SignupsContentPanelComponent < ApplicationComponent
    include Signups::Types

    BACKGROUND_IMAGE_HTML_ID = "backgroundimage"
    FOREGROUND_IMAGE_HTML_ID = "image"
    DEFAULT_BACKGROUND_IMAGE_URL = "/images/signup/bg-darkest-medium@2x.webp"
    DEFAULT_FOREGROUND_IMAGE_URL = "/images/signup/tres-amigos@2x.webp"
    DEFAULT_FOREGROUND_IMAGE_ALT_TEXT = "GitHub Mascots Mona, Copilot, and a rubber duck floating together."
    # On smaller screen sizes, show 2 mascot heads rather than 3 mascots
    RESPONSIVE_FOREGROUND_IMAGE_URL = "/images/signup/dos-amigos@2x.webp"

    sig { params(custom_page_param: T.nilable(String), contentful_custom_content_entry: T.nilable(T::Hash[Symbol, T.untyped])).void }
    def initialize(custom_page_param: nil, contentful_custom_content_entry: nil)
      @custom_page_param = custom_page_param
      @contentful_custom_content_entry = contentful_custom_content_entry
    end

    sig { returns(T.nilable(String)) }
    def background_image_url
      return DEFAULT_BACKGROUND_IMAGE_URL unless custom_content_enabled?

      assets = contentful_custom_content_entry&.[](:assets)
      return DEFAULT_BACKGROUND_IMAGE_URL if assets.blank?

      custom_background_url = assets.find { |asset| asset[:html_id] == BACKGROUND_IMAGE_HTML_ID }&.dig(:url)

      custom_background_url || DEFAULT_BACKGROUND_IMAGE_URL
    end

    sig { returns(String) }
    def foreground_image_url
      return DEFAULT_FOREGROUND_IMAGE_URL unless custom_content_enabled?

      assets = contentful_custom_content_entry&.[](:assets) || []

      assets.find { |asset| asset[:html_id] == FOREGROUND_IMAGE_HTML_ID }&.dig(:url) || DEFAULT_FOREGROUND_IMAGE_URL
    end

    # On smaller screen sizes, show 2 mascot heads rather than 3 mascots if no custom foreground image is provided.
    # Since the mascots are very specific and GitHub branded, we are making an accommodation for smaller screens.
    # To avoid complexity, if a custom foreground image is provided, we will resize that image on smaller screens rather than having tn editor upload 2 images.
    sig { returns(String) }
    def responsive_foreground_image_url
      if foreground_image_url == DEFAULT_FOREGROUND_IMAGE_URL
        RESPONSIVE_FOREGROUND_IMAGE_URL
      else
        foreground_image_url
      end
    end

    sig { returns(String) }
    def foreground_image_alt_text
      assets = contentful_custom_content_entry&.[](:assets) || []

      assets.find { |asset| asset[:html_id] == FOREGROUND_IMAGE_HTML_ID }&.dig(:alt_text) || DEFAULT_FOREGROUND_IMAGE_ALT_TEXT
    end

    private

    sig { returns(T::Boolean) }
    def validate_custom_param
      @custom_page_param.present?
      # Will add more validations via this issue: https://github.com/github/new-user-experience/issues/710
    end

    sig { returns(T::Boolean) }
    def custom_content_enabled?
      validate_custom_param && !!contentful_custom_content_entry
    end

    sig { returns(T.nilable(String)) }
    attr_reader :custom_page_param

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    attr_reader :contentful_custom_content_entry
  end
end
