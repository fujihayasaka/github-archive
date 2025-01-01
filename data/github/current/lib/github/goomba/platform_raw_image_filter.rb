# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Replaces the source of images linking to blobs with the absolute raw blob URL with or
  # without a token depending on the privacy of the repository. This is especially helpful
  # for private repositories, where the raw image URL needs a token to access the content at
  # raw.githubusercontent.com.
  #
  #   Example: <img src="/user/repo/blob/treeish/path.jpg">
  #   Becomes: <img src="https://raw.githubusercontent.com/user/repo/master/treeish/path.jpg?token='path-token'">
  #
  # This filter should be run after RelativeLinkFilter
  class PlatformRawImageFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("img")

    # Public: Retrieves a Hash mapping elements processed by this filter to
    # their original src attributes.
    #
    # Returns a Hash of Goomba::ElementNode to String.
    def self.non_raw_image_urls(scratch)
      scratch[:non_raw_image_urls] || {}
    end

    def initialize(*args)
      super
      @filter = GitHub::HTML::Filter.new("", context, result)
      scratch[:non_raw_image_urls] = {}
    end

    def selector
      SELECTOR
    end

    def call(element)
      original_src = element["src"]
      new_src = make_raw_url(original_src)
      return unless new_src

      element["src"] = new_src
      non_raw_image_urls[element] = original_src

      element
    end

    private

    def blob_url
      %r{
        \A
        (#{GitHub.url})? # Absolute GitHub URL, optional
        /([^/]+)         # user
        /([^/]+)         # repo
        /blob            # string literal "blob"
        /([^/]+)         # ref or branch name
        /(.*)            # treeish and path
        \z
      }x
    end

    def non_raw_image_urls
      self.class.non_raw_image_urls(scratch)
    end

    def make_raw_url(url)
      return unless url

      new_url = raw_url(url)
      return if new_url == url
      new_url
    end

    # Replace the blob URL with a raw URL
    def raw_url(link)
      if md = blob_url.match(link)
        name_with_owner = "#{md[2]}/#{md[3]}"
        ref = md[4]
        path = md[5]
        repository = find_repository(name_with_owner)
        return unless can_access_repo?(repository)

        url = TreeEntryRenderHelper.raw_blob_url(
          context[:current_user],
          repository,
          ref,
          path,
          expires_key: :blob,
        )
        url
      end
    end

    def find_repository(name_with_owner)
      @filter.find_repository(name_with_owner)
    end

    def can_access_repo?(repo)
      @filter.can_access_repo?(repo)
    end
  end
end
