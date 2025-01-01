# typed: strict
# frozen_string_literal: true

module Copilot
  module ContentExclusion
    class UrlNormalizer
      extend T::Helpers

      NormalizationError = Class.new(StandardError)

      SCHEMES = T.let(%w[ssh https http git].freeze, T::Array[String])
      ADO_HOSTS = T.let(%w[dev.azure.com visualstudio.com].freeze, T::Array[String])
      REGEX_SCHEME = T.let(/\A[\w+]+:\/\//.freeze, Regexp)
      REGEX_GIT_SSH = T.let(/\A(git|ssh)\+(git|ssh)/.freeze, Regexp)
      REGEX_TRAILING_GIT = T.let(/\/?\.git\/?\z/.freeze, Regexp)
      REGEX_LEADING_SLASH = T.let(/\A\//.freeze, Regexp)
      REGEX_V3_PATH = T.let(/\Av3\//i.freeze, Regexp)
      REGEX_DEFAULT_COLLECTION = T.let(/\ADefaultCollection\//i.freeze, Regexp)
      REGEX_GIT_PATH_SEGMENTS = T.let(/_git(?:\/_optimi[zs]ed|\/_full)?\//i.freeze, Regexp)
      REGEX_HTTPS = T.let(/\Ahttps?/.freeze, Regexp)

      sig { returns(T::Hash[String, NormalizedUrl]) }
      attr_reader :normalized_urls

      sig { void }
      def initialize
        @normalized_urls = T.let({}, T::Hash[String, NormalizedUrl])
      end

      # This function checks if two repository URLs are equal. It first normalizes the URLs, then compares them. If the
      # URLs are not exactly the same, we check if they will match under a wildcarded path. Otherwise, it returns false.
      #
      # @param match_pattern [String] The first URL to compare. Can be partial, monalisa/*
      # @param url [String] The second URL to compare. A true and proper url: git@github.com:monalisa/smile
      #
      # @return [Boolean] True if the URLs are considered equal, false otherwise.
      sig { params(match_pattern: String, url: String).returns(T::Boolean) }
      def match?(match_pattern, url)
        # Well yeah, if the strings are the same, lets avoid some complexity
        return true if match_pattern == url
        return true if match_pattern == "*"
        normalized_urls[match_pattern] ||= normalize!(match_pattern)
        normalized_urls[url] ||= normalize!(url)

        normalized_urls[match_pattern] == T.must(normalized_urls[url])
      end

      # This function normalizes a repository URL.
      # A URL must contain one of the supported schemes "ssh", "https", "http",
      # or "git", and raises an error for any other schemes. If the URL does not have a scheme, it assumes it's in the
      # scp-like format "<host>:<path>", and parses the host and path parts, and then removes a trailing ".git" or ".git/"
      # suffix from the path. We raises an error if the host contains a wildcard, or
      # if the path contains more than one wildcard. Finally, it returns a hash with the normalized host and path
      #
      # @param url_string [String] The URL to normalize.
      # @return [Hash] A hash with the keys :host and :path, containing the normalized host and path.
      sig { params(url_string: String).returns(GitHub::Result) }
      def normalize(url_string)
        GitHub::Result.new do
          url = T.let(nil, T.nilable(URI::Generic))

          # We first check if the may have a scheme, as `git@github.com:monalisa/smile` does not
          begin
            if REGEX_SCHEME.match?(url_string)
              url_string = url_string.gsub(REGEX_GIT_SSH, "ssh")
              url = URI.parse(url_string)
              raise NormalizationError, "Invalid scheme: '#{url.scheme}'" unless SCHEMES.include?(url.scheme)
            else
              # Here we conform scp-like, <host>:<path>
              host_part, path_part = url_string.split(":", 2)
              # the host will be the later part of a git@github.com
              maybe_host = T.must(host_part).split("@", 2).reverse.first

              if maybe_host&.include?("*")
                # Because a host like: `asdf.*.com.*` is valid to us, but not a "valid hostname"
                #    we parse w/o the hostname, and set it after.
                url = URI.parse("/#{path_part}")
                url.host = maybe_host # this avoids the `check_host` method triggering
              else
                url = T.let(URI::Generic.build(host: maybe_host, path: path_part), URI::Generic)
              end
            end
          rescue URI::Error
            raise NormalizationError, "Malformatted url '#{url_string}'"
          end

          path = T.must(url.path).downcase
          host = T.must(url.host).downcase

          # removes a trailing .git _or_ .git/ suffix
          path = path.gsub(REGEX_TRAILING_GIT, "").gsub(REGEX_LEADING_SLASH, "")

          # We need to sepcial case handle AzureDevOps (ADO) scheme urls. We do this first, as hosts will not match all the time.
          if ADO_HOSTS.any? { |h| host.end_with?(h) }
            # Sometimes the path can start with v3/, which is not needed
            # We need to remove DefaultColelction from the path, as it's not needed
            # We need to remove _git path segments (including suffixes), as they are not needed
            path = path.gsub(REGEX_V3_PATH, "").gsub(REGEX_DEFAULT_COLLECTION, "").gsub(REGEX_GIT_PATH_SEGMENTS, "")

            # if we are in http/s, there _could_ be a subdomain with the org name, so we need to handle that
            # take org.visualstudio.com for example. It will be vs-ssh.visualstudio.com if we're in SCP format
            if REGEX_HTTPS.match?(url.scheme) && host.ends_with?("visualstudio.com")
              segments = host.split(".")
              path = "#{segments.first}/#{path}" if segments.size > 2
            end

            # No matter which we ADO we send in, we want to normalize to dev.azure.com
            host = "dev.azure.com"
          end

          NormalizedUrl.new(host:, path:)
        end
      end

      sig { params(url_string: String).returns(NormalizedUrl) }
      def normalize!(url_string)
        normalize(url_string).value!
      end

      # ---

      class NormalizedUrl < T::Struct

        include GitHub::Memoizer

        const :host, String
        const :path, String

        sig { returns(Regexp) }
        memoize def regex
          # escaped, so `.` turns into `\.` and `*` turns into `\*`
          exp = Regexp.escape(to_s)
          #    but we want `*` to remain a regex wildcard
          #    * in escaped regex is `\\*`, so we need to replace that with `.*`
          exp = exp.gsub(/(\\\*)+/, ".*")
          Regexp.new("\\A#{exp}\\z", "i")
        end

        sig { returns(String) }
        memoize def to_s
          "#{host}/#{path}"
        end

        sig { params(other: NormalizedUrl).returns(T::Boolean) }
        def ==(other)
          # if they are the same, then they are the same
          return true if to_s.eql?(other.to_s)

          regex.match?(other.to_s)
        end
      end
    end
  end
end
