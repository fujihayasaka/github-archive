# typed: true
# frozen_string_literal: true

require "sourcemap"

module GitHub
  class SourceMapResolver
    DIRECTIVE_RE = /^(?:\/\/|\/\*)#\s*sourceMappingURL\s*=([^*\s]+)\s*(?:\*\/)?$/

    def initialize(asset_root)
      @asset_root = asset_root
      @maps = {}
    end

    # Finds the source file referenced at a line and column position in a
    # compiled bundle file that was served to browsers in production.
    #
    # url    - The compiled bundle's file name.
    # line   - The line number in the compiled bundle.
    # column - The column number in the compiled bundle.
    #
    # Examples
    #
    #   resolver = GitHub::SourceMapResolver.new("public/assets")
    #   resolver.resolve(url: "https://github.githubassets.com/assets/github-bootstrap-deadbeef.js", line: 1, column: 42)
    #   # => "app/assets/modules/github/remote.ts"
    #
    # Returns the String source file name or nil if not found.
    sig { params(url: String, line: Integer, column: Integer).returns(T.nilable(String)) }
    def resolve(url:, line:, column:)
      bundle = File.join(@asset_root, File.basename(url))
      map_for(bundle).bsearch(SourceMap::Offset.new(line, column))&.source
    end

    def stacktrace?(error)
      error[:stacktrace].any? do |frame|
        frame[:filename].include?(GitHub.asset_host_url.presence || GitHub.url)
      end
    end

    private

    def map_for(bundle)
      @maps[bundle] ||= begin
        if json = map_json(bundle)
          begin
            SourceMap::Map.from_json(json)
          rescue ::JSON::ParserError
            SourceMap::Map.new
          end
        else
          SourceMap::Map.new
        end
      end
    end

    def map_json(bundle)
      if name = map_file_name(bundle)
        full = File.expand_path(name, File.dirname(bundle))
        File.exist?(full) ? File.read(full) : nil
      else
        nil
      end
    rescue # rubocop:todo Lint/GenericRescue
      nil
    end

    def map_file_name(bundle)
      if File.exist?(bundle)
        data = File.read(bundle)
        match = DIRECTIVE_RE.match(data)
        match ? match[1] : nil
      else
        nil
      end
    rescue # rubocop:todo Lint/GenericRescue
      nil
    end
  end
end
