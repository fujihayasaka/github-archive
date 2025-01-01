# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class ChangesetSchedule
      def initialize(changesets)
        @active_changesets = Hash.new { |h, k| h[k] = {} }
        @release_constraints = {}
        @valid_changesets = []

        changesets.each do |changeset|
          changeset = OpenApi::Description::Changeset.from(changeset)
          @valid_changesets << changeset
          @release_constraints[changeset.name] = changeset.releases
          @active_changesets[changeset.version][changeset.name] = changeset
        end

        # Cache for changeset_active? lookups
        @memoized_active_statuses = {}
      end

      # Determine if a changeset is active for a given version.
      #
      # @note The result is memoized to avoid repeated iteration
      #   over versions.
      #
      # @param version [String, Symbol] the API version to check
      # @param changeset [String] the name of the changeset
      #
      # @return [Boolean]
      def changeset_active?(release:, version:, changeset:)
        if version == Api::Versioning::NEXT_VERSION
          version = Api::Versioning::NEXT_VERSION_SYM
        end

        return false unless changeset_valid?(changeset)

        key = [version, changeset]

        if @memoized_active_statuses.key?(key)
          @memoized_active_statuses[key]
        else
          @memoized_active_statuses[key] = meets_release_constraint?(release: release, changeset: changeset) && changeset_active_status(version, changeset)
        end
      end

      def fetch
        @active_changesets
      end

      # Fetch a changesets api version
      #
      # @param changeset [String] the name of the changeset
      #
      # @return [String]
      def changeset_version(changeset:)
        changeset = @valid_changesets.detect { |vcs| vcs.name == changeset }
        changeset.version if changeset
      end

      # Determine if a changeset is valid
      #
      # @note Invalid changesets are automatically inactive
      #
      # @param changeset [String] the name of the changeset
      #
      # @return [Boolean]
      def changeset_valid?(changeset)
        changeset = @valid_changesets.detect { |vcs| vcs.name == changeset }
        !!changeset
      end

      # Determine if a changeset meets a release constraint
      #
      # @param release [Release Object]
      # @param changeset [String] the name of the changeset
      #
      # @return [Boolean]
      def meets_release_constraint?(release:, changeset:)
        # changeset will not meet release constraint for ghes if it has not been promoted to a version (just in `next`)
        return false if @active_changesets.dig(:next, changeset) && release.name.match?(/ghes/)

        @release_constraints[changeset].any? do |release_constraint|
          case release_constraint
          when String
            return true if release_constraint == release.name
          when Hash
            if release_constraint.size == 1
              if release.version
                constraint_name, raw_requirement = release_constraint.flatten
                requirement = Gem::Requirement.create(raw_requirement)
                return true if constraint_name == release.name && requirement.satisfied_by?(release.version)
              end
            else
              raise OpenApi::Validation::Error, "Invalid release constraint: #{release_constraint.inspect}"
            end
          end
        end
      end

      private

      # Get the list of versions, sorted canonically from oldest to newest.
      #
      # @note The result is memoized to avoid repeated sorting.
      #
      # @return [Array<String, Symbol>]
      def ordered_versions
        @ordered_versions ||= Api::Versioning.sort_versions(Api::Versioning.usable_versions)
      end

      # Unmemoized, non-normalizing version of changeset_active?
      def changeset_active_status(version, changeset)
        return false if version.nil?
        return false unless Api::Versioning.usable_version?(version)
        return true if version == Api::Versioning::NEXT_VERSION_SYM

        if @active_changesets.dig(version, changeset)
          true
        else
          ordered_versions.take_while { |v| v != version && v != Api::Versioning::NEXT_VERSION_SYM }.each do |v|
            return true if @active_changesets.dig(v, changeset) && Date.parse(v) <= Date.parse(version)
          end
          false
        end
      end
    end
  end
end
