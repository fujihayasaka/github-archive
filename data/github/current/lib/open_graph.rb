# typed: true
# frozen_string_literal: true

class OpenGraph
  # This processor is used to skip encoding the resource url,
  # since that should already be handled by #permalink.
  class UrlProcessor
    def self.transform(name, value)
      return value if name == "resource_url"
      Addressable::URI.encode_component(value)
    end
  end

  # https://opengraph.githubassets.com/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855/monalisa/repo
  URI_TEMPLATE = Addressable::Template.new("{+og_image_generator_base_url}/{cache_key}{+resource_url}").freeze

  IMAGE_WIDTH = 1200
  IMAGE_HEIGHT = 600

  def initialize(resource, cache_key_parts: [])
    @resource = resource
    @resource_klass = resource.class.name.downcase
    @cache_key_parts = cache_key_parts.presence || [resource.updated_at]
  end

  # Public: URL intended for the `og:image` meta tag
  #
  # Returns a fully qualified url string.
  def og_image_url
    GitHub.dogstats.increment("open_graph.image_url", tags: ["resource:#{@resource_klass}"])

    URI_TEMPLATE.expand(
      {
        og_image_generator_base_url: GitHub.og_image_generator_base_url,
        cache_key: cache_key,
        resource_url: resource_path,
      },
      GitHub.flipper[:skip_open_graph_url_encoding].enabled? ? UrlProcessor : nil,
    ).to_s
  end

  private

  # Private: Build a path for the given resource (repo, pr, issue, commit)
  #
  # Each resource has a standard permalink method to do this work.
  #
  # Returns a relative URL path as a string.
  def resource_path
    @resource.permalink(include_host: false)
  end

  # Private: Build a SHA using the parts array that initialized this class.
  #
  # The cache key is used by the internal opengraph image service and as the
  # parts change, the cache will be busted, thereby forcing an updated image
  # to be returned from the service.
  #
  # Returns a hexdigest SHA as a string.
  def cache_key
    Digest::SHA256.hexdigest(@cache_key_parts.join(":"))
  end
end
