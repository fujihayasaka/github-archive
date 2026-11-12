# frozen_string_literal: true

require 'uri'

module AdvisoryDBToolkit::Ecosystems
  # SafeUrl builds outbound registry URLs from a *trusted, hard-coded* base
  # endpoint and one or more *untrusted* path parts (e.g. a user supplied
  # package name).
  #
  # It exists to replace `URI.join(BASE, user_input)` which is unsafe: when
  # `user_input` is itself an absolute URL (`http://localhost:4646/...`),
  # protocol-relative (`//evil/...`), or rooted (`/etc/passwd`), `URI.join`
  # follows RFC 3986 reference resolution and lets the second argument
  # *replace* the scheme, authority, and/or path of the base, turning a
  # registry lookup into a full SSRF primitive
  # (see github/team-advisory-database#6540, HackerOne report 3687095).
  #
  # SafeUrl never resolves the untrusted input as a URI reference. It treats
  # it strictly as opaque path data:
  #
  #   * Each `/`-separated segment is percent-encoded with
  #     `URI.encode_uri_component`, so `:`, `@`, `?`, `#`, `[`, `]`, `\`,
  #     spaces, control characters, etc. cannot change the authority, scheme,
  #     query, or fragment of the constructed URL.
  #   * `/` is preserved *between* segments because several ecosystems
  #     legitimately need it (npm scopes `@scope/name`, Go module paths,
  #     Composer `vendor/package`, GitHub Actions `owner/repo`).
  #   * Empty segments (`""`) and dot segments (`.`, `..`) are rejected so the
  #     result can never normalize to a different path prefix on the host.
  #   * The constructed URL is asserted to share scheme, host and port with
  #     the base endpoint as a final tripwire.
  module SafeUrl
    extend self

    DOT_SEGMENTS = [".", ".."].freeze

    class UnsafePathError < ArgumentError; end

    # Build a URL by appending untrusted path parts onto a trusted base.
    #
    # @param base_endpoint [String] hard-coded absolute URL (scheme + host).
    # @param parts [Array<String>] untrusted path components.
    # @return [URI::Generic] a URI guaranteed to share scheme/host/port with
    #   `base_endpoint`.
    # @raise [ArgumentError] if the base is not absolute.
    # @raise [UnsafePathError] if any part is nil, empty, or contains an
    #   empty / dot segment.
    def build(base_endpoint, *parts)
      base = URI.parse(base_endpoint)
      unless base.is_a?(URI::HTTP) && base.host
        raise ArgumentError, "base endpoint must be an absolute http(s) URL"
      end

      encoded = parts.flat_map { |part| encode_part(part) }

      result = base.dup
      result.path = join_path(base.path, encoded)

      # `URI#path=` cannot change scheme/authority, but assert anyway so a
      # future refactor cannot silently reintroduce the SSRF.
      unless result.scheme == base.scheme && result.host == base.host && result.port == base.port
        raise UnsafePathError, "constructed URL escaped the base endpoint"
      end

      result
    end

    private

    def encode_part(part)
      raise UnsafePathError, "path part must not be nil" if part.nil?

      segments = part.to_s.split("/", -1)
      raise UnsafePathError, "path part must not be empty" if segments.empty?

      segments.map do |segment|
        if segment.empty? || DOT_SEGMENTS.include?(segment)
          raise UnsafePathError, "path part contains an empty or dot segment: #{part.inspect}"
        end
        encode_segment(segment)
      end
    end

    # `URI.encode_uri_component` (Ruby >= 3.1) percent-encodes every byte that
    # is not an RFC 3986 unreserved character. In particular it encodes `/`,
    # `:`, `@`, `?`, `#`, `[`, `]`, `\` and whitespace, which is exactly what
    # we need to keep untrusted input confined to a single path segment.
    def encode_segment(segment)
      URI.encode_uri_component(segment)
    end

    def join_path(base_path, encoded_segments)
      prefix = base_path.to_s.chomp("/")
      "#{prefix}/#{encoded_segments.join("/")}"
    end
  end
end
