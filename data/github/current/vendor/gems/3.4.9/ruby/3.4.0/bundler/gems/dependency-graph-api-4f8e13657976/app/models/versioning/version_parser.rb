module Versioning
  class VersionParser
    WILDCARDS = %w(* x)
    SEMANTIC_PATTERN = /\A
      (?<major>\d+)\.?
      (?<minor>\d+|\*|x)?\.?
      (?<patch>\d+|\*|x)?\.?
      (?<rest>.*)
    /x

    PRERELEASE_IDENTIFIER = "-"
    METADATA_IDENTIFIER = "+"

    def self.parse(version, allow_named_versions: false)
      new(version, allow_named_versions: allow_named_versions).parsed || UnparseableVersion.new(version)
    end

    attr_reader :allow_named_versions

    def initialize(version, allow_named_versions: false)
      #Get major minor and patch via regex
      @version = version

      @allow_named_versions = allow_named_versions
      if GenericVersionParser.valid_named_version?(allow_named_versions, version)
        @primary_identifier = @version
        return
      end

      build_and_assign_semver_parts
    end

    def parsed
      return unless valid?

      GenericVersionParser.generate(
        allow_named_versions: allow_named_versions,
        primary_identifier: primary_identifier,
        minor: minor,
        patch: patch,
        additional_fields: additional_fields,
        prerelease: prerelease,
        metadata:   metadata,
      )
    end

    private
    attr_reader :version, :primary_identifier, :minor, :patch, :additional_fields, :prerelease, :metadata, :valid_additional_fields

    def build_and_assign_semver_parts
      normalized = @version.downcase.sub(/^[^\d]*/, "")
      parts = normalized.match(SEMANTIC_PATTERN) || {}

      return unless parts[:major].present?

      @major = parts[:major].to_i
      @minor = parse_parts(@major, parts[:minor])
      @patch = parse_parts(@minor, parts[:patch])

      @primary_identifier = @major

      build_and_assign_affixes(parts[:rest]) if parts[:rest].present?
    end

    def build_and_assign_affixes(affixes)
      rest, @metadata = affixes.split(METADATA_IDENTIFIER, 2)

      # the prerelease can be designated by the prerelease identifier
      if rest.include?(PRERELEASE_IDENTIFIER)
        rest, @prerelease = rest.split(PRERELEASE_IDENTIFIER, 2)

      # or we can designate the prerelease by containing a letter - in which case it's the last clause
      elsif rest.match?(/[a-z|A-Z]/)
        components = rest.split(".")

        # Handle pre-releases like "beta.1"
        # We're testing if the first component is a string and the rest are all integers:
        if components.first.match?(/\D+/) && components[1..-1]&.all? { |p| p.match?(/\d+/) }
          @prerelease = components.join(".")
          rest = "" # Set rest to an empty string because we just used it to construct our prerelease.
        else
          rest = components[0..-2].join(".")
          @prerelease = components[-1]
        end
      # or we have no prerelease
      else
        @prerelease = nil
      end

      # additional_fields are an array of the .-seperated components we have left
      # We will mark them as invalid if they aren't just integers
      split_rest = rest.split(".")
      @valid_additional_fields = split_rest.empty? || split_rest.all? { |piece| /\d+/.match(piece) }
      @additional_fields = split_rest.map(&:to_i)
    end

    def valid?
      primary_identifier.present? && (additional_fields.present? ? valid_additional_fields : true)
    end

    # Helper to parse parts of a version string and ensure that we account for everything.
    def parse_parts(part_above, our_parts)
      if our_parts.present?
        our_parts.in?(WILDCARDS) ? Float::INFINITY : our_parts.to_i
      else
        if part_above == Float::INFINITY
          Float::INFINITY
        else
          nil
        end
      end
    end

    class UnparseableVersion
      include Comparable

      def initialize(version)
        # We'd like to keep track of when we have an UnparseableVersion, so we'll do two things:
        #   - Increment a counter in Datadog so we can have a high level overview and monitors.
        #   - Log the incident in Splunk, which should contain much richer metadata we could use for debugging.
        #
        ::Instrument.increment("unparseable_version")
        DependencyGraph.logger.info(
          "gh.dependency_graph.version_parser.unparseable_version" => version,
          "gh.dependency_graph.version_parser.failed" => true,
        )

        @version = version
      end

      def parseable?
        false
      end

      def encoded
        nil
      end

      def <=>(other)
        -1
      end

      # Below we're defining methods which will either return 0 or nil. This is because we don't want
      # the UnparseableVersion to cause exceptions in existing code. Instead, we will do the same
      # thing that we did before transitioning completely which was to return upper and lower bounds
      # of "0.0.0" - by returning primary_identifier/minor/patch as 0 and additional_fields/prerelease/metadata
      # as nil, we can make this happen. We don't care that we're returning this incorrect data for
      # unparsable versions because we're logging the version string in #initialize for debugging.
      #
      # Define methods which return 0
      %i(primary_identifier minor patch).each do |method_name|
        define_method(method_name) { 0 }
      end

      # Define methods which return nil
      %i(additional_fields prerelease metadata).each do |method_name|
        define_method(method_name) { nil }
      end

      def most_specified
        :patch
      end
    end
  end
end
