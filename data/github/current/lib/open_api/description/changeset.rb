# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    # Changesets are collections of [breaking] changes to the OpenAPI description,
    # include additional metadata for documentation, and are released as part of
    # an API calendar version.
    class Changeset
      NAME_PATTERN = /\A[a-z][_a-z0-9]+\Z/
      ALLOWED_KEYS = %w[name created_at description ready_to_ship_on_or_after releases version notes owner]
      REQUIRED_KEYS = %w[name created_at description releases version owner]

      # Normalize a changeset from a Hash or Changeset instance.
      #
      # @param changeset [Hash, Changeset]
      #
      # @raise [ArgumentError] if `changeset` is not a Hash or Changeset
      #
      # @return [Changeset]
      def self.from(changeset)
        case changeset
        when self
          changeset
        when Hash
          new(changeset)
        else
          raise ArgumentError, "changeset must be a Hash or Changeset"
        end
      end

      # Determine if the name of the changeset is valid.
      #
      # @param name [String] the name of the changeset
      #
      # @return [Boolean]
      def self.valid_name?(name)
        NAME_PATTERN.match?(name)
      end

      # The release schedule for changesets.
      #
      # @return [OpenApi::Description::ChangesetSchedule]
      def self.schedule
        @schedule ||= ChangesetSchedule.new(all)
      end

      # All defined changesets.
      #
      # @return [Array<OpenApi::Description::Changeset>]
      def self.all
        OpenApi.root.glob("changesets/*.yaml").map do |file|
          new(YAML.safe_load(File.read(file)), file.basename)
        end
      end

      # Find the path to a changeset file.
      #
      # @param changeset_name [String] the name of the changeset
      #
      # @return [Pathname]
      def self.find_path(changeset_name)
        OpenApi.root.join("changesets").glob("[0-9]*_#{changeset_name}.yaml").first
      end

      # @param changeset [Hash] the raw changeset data
      def initialize(changeset, filename = nil)
        @raw = changeset
        @filename = filename
        validate!
      end

      attr_reader :raw, :filename

      # The name of the changeset.
      #
      # @return [String]
      def name
        @name ||= @raw["name"]
      end

      # The timestamp of when the changeset was created.
      #
      # @return [Integer]
      def created_at
        @created_at ||= @raw["created_at"]
      end

      # The description of the changeset.
      #
      # @return [String]
      def description
        @description ||= @raw["description"]
      end

      # Notes detailing the nature of the change and/or its effects.
      #
      # @return [String]
      def notes
        @notes ||= @raw["notes"]
      end

      # The date on or after which this changeset can be promoted into a fixed version.
      #
      # @return [String, nil]
      def ready_to_ship_on_or_after
        @ready_to_ship_on_or_after ||= @raw["ready_to_ship_on_or_after"]
      end

      # The API releases that this changeset applies to.
      #
      # @return [String, Symbol]
      def releases
        @releases ||= @raw["releases"]
      end

      # The API version that this changset was promoted to.
      #
      # @return [String, Symbol] the version identifier
      def version
        @version ||= case @raw["version"]
        when nil, Api::Versioning::NEXT_VERSION
          Api::Versioning::NEXT_VERSION_SYM
        else
          @raw["version"]
        end
      end

      # The owning team.
      #
      # @return [String]
      def owner
        @owner ||= @raw["owner"]
      end

      private

      def validate!
        unknown_keys = @raw.keys - ALLOWED_KEYS
        unless unknown_keys.empty?
          raise InvalidChangesetError, "Unknown changeset properties: #{unknown_keys}"
        end

        missing_keys = REQUIRED_KEYS - @raw.keys
        unless missing_keys.empty?
          raise InvalidChangesetError, "Missing required properties: #{missing_keys}"
        end

        unless self.class.valid_name?(@raw["name"])
          raise InvalidChangesetNameError, @raw["name"]
        end
      end
    end
  end
end
