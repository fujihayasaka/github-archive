# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Replaces the source of images linking to blobs with the raw URL, allowing
  # users to easily link to images in a repository. This is especially helpful
  # for private repositories, where the raw image URL gets redirected to
  # raw.githubusercontent.com with a token that expires.
  #
  #   Example: <img src="/user/repo/blob/treeish/path.jpg">
  #   Becomes: <img src="/user/repo/raw/treeish/path.jpg">
  #
  # This filter should be run after RelativeLinkFilter
  class RawImageFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("img, picture")
    PICTURE_CHILD_SELECTOR = Goomba::Selector.new("img, source")

    # Public: Retrieves a Hash mapping elements processed by this filter to
    # their original src attributes.
    #
    # Returns a Hash of Goomba::ElementNode to String.
    def self.non_raw_image_urls(scratch)
      scratch[:non_raw_image_urls] || {}
    end

    def initialize(*args)
      super
      @filter = GitHub::HTML::RawImageFilter.new("", context, result)
      scratch[:non_raw_image_urls] = {}
    end

    def selector
      SELECTOR
    end

    URL_ATTRIBUTES = {
      img: "src",
      source: "srcset",
    }.freeze

    def call(element)
      if URL_ATTRIBUTES[element.tag]
        process(element)
      elsif element.tag.nil? # goomba doesn't recognize <picture> and sets element.tag to nil
        element.select(PICTURE_CHILD_SELECTOR).each do |child|
          process(child) if URL_ATTRIBUTES[child.try(:tag)]
        end
      end
    end

    private

    def process(element)
      attribute = URL_ATTRIBUTES[element.tag]
      original_url = element[attribute]
      new_url = @filter.make_raw_url(original_url)
      return unless new_url

      element[attribute] = new_url
      non_raw_image_urls[element] = original_url

      element
    end

    def non_raw_image_urls
      self.class.non_raw_image_urls(scratch)
    end
  end
end
