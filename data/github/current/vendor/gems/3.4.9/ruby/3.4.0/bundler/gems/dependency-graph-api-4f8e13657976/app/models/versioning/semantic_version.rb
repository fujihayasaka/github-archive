module Versioning
  class SemanticVersion < Version

    attr_reader :major, :minor, :patch, :additional_fields, :prerelease, :metadata, :most_specified

    def initialize(major:, minor: nil, patch: nil, additional_fields: [], prerelease: nil, metadata: nil)
      @major = major
      @most_specified = :major

      if minor.present?
        @minor = minor
        @most_specified = :minor
      else
        @minor = 0
      end

      if patch.present?
        @patch = patch
        @most_specified = :patch
      else
        @patch = 0
      end

      if additional_fields.present?
        @additional_fields = additional_fields
        @most_specified = :additional_fields
      else
        @additional_fields = []
      end

      @prerelease = prerelease
      @metadata   = metadata
    end

    def primary_identifier
      @major
    end

    def ==(other)
      return false unless other.is_a?(SemanticVersion)

      major == other.major &&
        minor == other.minor &&
        patch == other.patch &&
        additional_fields == other.additional_fields &&
        prerelease == other.prerelease &&
        metadata == other.metadata
    end

    def <=>(other)
      if other.is_a?(SemanticVersion)
        sort = (major <=> other.major).nonzero? ||
               (minor <=> other.minor).nonzero? ||
               (patch <=> other.patch).nonzero? ||
               (additional_fields <=> other.additional_fields).nonzero? ||
               (comparable_prerelease <=> other.comparable_prerelease).nonzero? ||
               0

        return sort
      end

      super
    end

    def encoded
      EncodedVersion.new(self)
    end

    def hash
      to_s.hash
    end

    def to_s
      "#{major}.#{human_minor}.#{human_patch}#{human_additional_fields}#{human_prerelease}#{human_metadata}"
    end

    def inspect
      to_s
    end

    def parseable?
      true
    end

    protected

    def comparable_prerelease
      ComparablePrerelease.new(prerelease)
    end

    private

    def human_minor
      minor == Float::INFINITY ? "x" : minor
    end

    def human_patch
      patch == Float::INFINITY ? "x" : patch
    end

    def human_additional_fields
      ".#{additional_fields.join('.')}" if additional_fields.present?
    end

    def human_prerelease
      "-#{prerelease}" if prerelease.present?
    end

    def human_metadata
      "+#{metadata}" if metadata.present?
    end

    class ComparablePrerelease
      DELIMITER = "."

      def initialize(identifier)
        @identifier = identifier
      end

      def <=>(other)
        return 0  if parts.none? && other.parts.none?
        return 1  if parts.none?
        return -1 if other.parts.none?

        [parts.length, other.parts.length].max.times
          .map { |i| compare_component(parts[i], other.parts[i]) }
          .detect(&:present?) || 0
      end

      protected

      def parts?
        parts.any?
      end

      def parts
        @parts ||= identifier.present? ? identifier.split(DELIMITER) : []
      end

      private

      attr_reader :identifier

      def compare_component(left, right)
        return 1 if right.blank?
        return -1 if left.blank?

        if numeric?(left)
          numeric?(right) ? (left.to_i <=> right.to_i).nonzero? : -1
        elsif numeric?(right)
          1
        else
          (left <=> right).nonzero?
        end
      end

      def numeric?(component)
        component[/^\d+$/]
      end
    end
  end
end
