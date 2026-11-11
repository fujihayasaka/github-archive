# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Relative link filter modifies relative links in markdown based on viewing
  # location, making it so these links lead to the correct destination whether
  # viewed locally, as a blob, or (in the case of a README), as part of a tree
  # view.
  #
  # Requires values passed in the context:
  #
  # entity     - must be a repository; skips otherwise
  # path       - path where this markdown content is being shown
  #              (e.g. "README.md", "nested/dir", or "")
  # committish - committish for this markdown content
  #              (branch name, ref name, commit oid)
  # view       - view where this markdown content is being shown
  #              (viz. :tree, :blob, :preview)
  class RelativeLinkFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("a, img, picture")
    PICTURE_CHILD_SELECTOR = Goomba::Selector.new("img, source")

    def self.cache_key(context)
      GitHub::HTML::RelativeLinkFilter.cache_key(context)
    end

    def initialize(*args)
      super
      @filter = GitHub::HTML::RelativeLinkFilter.new("", context, result)
    end

    def scan(_)
      @processed_nodes = []
    end

    def selector
      SELECTOR
    end

    URL_ATTRIBUTES = {
      a: "href",
      img: "src",
      source: "srcset",
    }.freeze

    def call(element)
      return nil unless @filter.should_process?
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
      return if @processed_nodes.include?(element) # Avoid double-expand on PictureFilter-less pipelines
      attribute = URL_ATTRIBUTES.fetch(element.tag)
      new_url = @filter.make_relative(element[attribute])
      return unless new_url

      element[attribute] = new_url
      @processed_nodes << element
      element
    end
  end
end
