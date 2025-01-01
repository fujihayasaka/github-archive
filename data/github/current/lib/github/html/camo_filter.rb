# typed: true
# frozen_string_literal: true

require "addressable/uri"

module GitHub::HTML
  # Override the default CamoFilter and provide our secret key.
  class CamoFilter < ::HTML::Pipeline::CamoFilter
    def self.cache_key(context)
      return "asset_proxy_disabled" if !GitHub.image_proxy_enabled?
      [
        "asset_proxy_url=#{(context[:asset_proxy] || GitHub.image_proxy_url)}",
        "asset_proxy_secret_key=#{(context[:asset_proxy_secret_key] || GitHub.image_proxy_key)}",
        "asset_proxy_allowlist=#{(context[:asset_proxy_allowlist]&.join(",") || GitHub.image_proxy_host_allowlist).join(",")}"
      ].reject(&:blank?).join(":")
    end

    def initialize(doc, starting_context = nil, result = nil)
      context = starting_context ? starting_context.dup : {}
      context[:asset_proxy] ||= GitHub.image_proxy_url
      context[:disable_asset_proxy] ||= !GitHub.image_proxy_enabled?
      context[:asset_proxy_secret_key] ||= GitHub.image_proxy_key
      context[:asset_proxy_allowlist] ||= GitHub.image_proxy_host_allowlist

      super(doc, context, result)
    end

    # Get the asset proxy URL for the given URI.
    #
    # Note that we instantiate a new empty filter to grab the default context
    # values, and that no allowlist checks are performed.
    def self.asset_proxy_url(uri, context = nil)
      camo = new(nil, context)
      if camo.asset_proxy_enabled?
        camo.asset_proxy_url(uri)
      else
        uri
      end
    end

    # We only support http and https
    ALLOWLISTED_SCHEMES = %w(http https).freeze

    # Internal: Does the URL contain only printable characters?
    #
    # We don't allow any non-printable characters (NULL, newlines, etc).
    # And we don't allow backslashes that might have slipped through
    def allowed_characters?(uri)
      uri.to_s =~ /\A(?!\\)[[:print:]]*\z/
    end

    # Internal: Is the given URI a simple relative URI?
    #
    # We only allow simple relative URIs such as `/foo/bar.gif`.  We do not
    # allow relative URIs such as `//github.com/foo/bar/gif`, `///foo/bar.gif`,
    # or any other ambiguous relative URI.
    def relative_uri?(uri)
      uri.relative?      &&
      uri.scheme.nil?    &&
      uri.userinfo.nil?  &&
      uri.host.nil?      &&
      uri.port.nil?      &&
      uri.path.present?  &&
      allowed_characters?(uri) &&
      !uri.path.start_with?("/\\")
    end

    # Internal: Is the given URI a simple absolute URI?
    #
    # We only allow simple absolute URIs such as
    # `https://github.com/foo/bar.gif`.  We do not allow absolute URIs such as
    # `https://foo:bar@github.com/foo/bar/gif`, `javascript://`,
    # `https:///foo/bar.gif`, or any other ambiguous absolute URI.
    def absolute_uri?(uri)
      !uri.relative?                           &&
      uri.scheme.present?                      &&
      ALLOWLISTED_SCHEMES.include?(uri.scheme) &&
      uri.userinfo.nil?                        &&
      uri.host.present?                        &&
      allowed_characters?(uri)
    end

    # Internal: Is the given URI on our asset allowlist?
    #
    # We only allow simple absolute URIs to our allowlist asset hosts.
    def allowlisted_host?(uri)
      absolute_uri?(uri) && asset_host_allowlisted?(uri.host)
    end

    def call
      return doc unless asset_proxy_enabled?

      doc.search("img").each do |element|
        camo_image_filter(element, source_attribute: "src")
      end

      doc.search("source").each do |element|
        camo_image_filter(element, source_attribute: "srcset")
      end

      doc
    end

    def camo_image_filter(element, source_attribute: "src")
      original_src = element[source_attribute]
      return unless original_src

      begin
        # Addressable::URI differentiates between relative URLS with leading
        # whitespace (ex. " //" vs "//"). We will perform all URL evaluation
        # without leading space, as browsers tend to ignore them. This should
        # help minimize the differences between how Addressable::URI and
        # browsers will interpret URLs.
        stripped_src = original_src.lstrip
        # To handle "srcset" values, we take only the first URL and ignore any following descriptors or additional URLs.
        # See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-srcset for more details.
        stripped_src, _ = stripped_src.split(/(\s+.*)?,/, 2) if source_attribute == "srcset"

        uri = Addressable::URI.parse(stripped_src)

        if uri.nil?
          element[source_attribute] = ""
        elsif relative_uri?(uri) || allowlisted_host?(uri)
          element[source_attribute] = uri.to_s
        elsif absolute_uri?(uri)
          element[source_attribute] = asset_proxy_url(uri.to_s)
          element["data-canonical-src"] = uri.to_s
        else
          element[source_attribute] = ""
        end
      rescue Addressable::URI::InvalidURIError
        element[source_attribute] = ""
      end
    end
  end
end
