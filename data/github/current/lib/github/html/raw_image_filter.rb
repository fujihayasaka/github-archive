# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # Replaces the source of images linking to blobs with the raw URL, allowing
  # users to easily link to images in a repository. This is especially helpful
  # for private repositories, where the raw image URL gets redirected to
  # raw.githubusercontent.com with a token that expires.
  #
  #   Example: <img src="/user/repo/blob/treeish/path.jpg">
  #   Becomes: <img src="/user/repo/raw/treeish/path.jpg">
  #
  # This filter should be run after RelativeLinkFilter
  class RawImageFilter < Filter
    BLOB_URL = %r{
      \A
      (#{GitHub.url})? # Absolute GitHub URL, optional
      /([^/]+)         # user
      /([^/]+)         # repo
      /blob            # string literal "blob"
      /(.*)            # treeish and path
      \z
    }x

    def call
      doc.search("img").each do |node|
        new_src = make_raw_url(node.attributes["src"].try(:value))
        next unless new_src
        node.attributes["src"].value = new_src
      end

      doc
    end

    def make_raw_url(url)
      return unless url

      new_url = raw_url(url)
      return if new_url == url
      new_url
    end

    private

    # Replace the blob URL with a raw URL
    def raw_url(link)
      if md = BLOB_URL.match(link)
        path = [md[1], md[2], md[3], "raw", md[4]].join("/")
        path
      end
    end
  end
end
