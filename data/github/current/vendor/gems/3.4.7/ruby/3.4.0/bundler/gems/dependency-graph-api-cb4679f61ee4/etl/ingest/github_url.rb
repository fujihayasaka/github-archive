require "active_support"
require "active_support/core_ext"

module Ingest
  class GitHubUrl
    HOST = "github.com"

    def initialize(url)
      @url = url.presence ? URI(url) : InvalidURI.new
    rescue URI::InvalidURIError
      @url = InvalidURI.new
    end

    def valid?
      url.host == HOST && path_components.count >= 2
    end

    def owner
      path_components[0]
    end

    def name
      path_components[1].sub(/.git$/, "")
    end

    private

    attr_reader :url

    def path_components
      @path_components ||= Array(url.path.to_s.split("/".freeze)[1..-1])
    end

    class InvalidURI
      def host; end
      def path; end
    end
  end
end
