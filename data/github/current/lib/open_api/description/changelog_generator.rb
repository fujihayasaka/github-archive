# typed: true
# frozen_string_literal: true

require "pathname"

module OpenApi
  module Description
    # Generates human-readable CHANGELOG.md files from changesets.
    #
    # Changelogs are organized per release (e.g., api.github.com, ghec, ghes-3.x)
    # and contain cumulative breaking changes across all API versions.
    class ChangelogGenerator
      # Mapping of release identifiers to display names.
      RELEASE_DISPLAY_NAMES = {
        "api.github.com" => "GitHub Free, Pro & Team",
        "ghec" => "GitHub Enterprise Cloud",
      }.freeze

      # Public: Generate changelogs for all releases.
      #
      # Returns an Array of file paths that were written.
      def self.generate_all(output_dir: nil, release_identifiers: nil, include_unpublished_releases: true)
        output_dir ||= OpenApi.root.join("changelogs")
        new(
          output_dir: output_dir,
          include_unpublished_releases: include_unpublished_releases,
        ).generate_all(release_identifiers: release_identifiers)
      end

      def initialize(output_dir:, include_unpublished_releases: true)
        @output_dir = Pathname.new(output_dir)
        @include_unpublished_releases = include_unpublished_releases
      end

      # Public: Generate changelogs for all releases.
      #
      # Returns an Array of generated changelog paths.
      def generate_all(release_identifiers: nil)
        all_changesets = OpenApi::Description::Changeset.all.reject { |changeset| changeset.version == :next }
        changesets_by_release = group_by_release(all_changesets, release_identifiers: release_identifiers)

        changesets_by_release.map do |release_name, changesets|
          generate_for_release(release_name, changesets)
        end
      end

      private

      # Private: Generate the changelog header with the release name.
      #
      # Returns a String of markdown.
      def changelog_header(release_name)
        display_name = display_name_for(release_name)
        <<~HEADER
          # REST API Breaking Changes for #{display_name}

          For more information about GitHub REST API versioning, see "[API Versions](https://docs.github.com/rest/overview/api-versions)".

        HEADER
      end

      # Private: Convert a release identifier to a display name.
      #
      # Returns a String.
      def display_name_for(release_name)
        return RELEASE_DISPLAY_NAMES[release_name] if RELEASE_DISPLAY_NAMES.key?(release_name)

        if release_name.start_with?("ghes-")
          version = release_name.delete_prefix("ghes-")
          return "GitHub Enterprise Server #{version}"
        end

        # Fall back to the identifier itself
        release_name
      end

      # Private: Group changesets by release name.
      #
      # Returns a Hash of { release_name => [changesets] }
      def group_by_release(changesets, release_identifiers: nil)
        release_groups = Hash.new { |hash, key| hash[key] = [] }
        release_filter = Array(release_identifiers)

        changesets.each do |changeset|
          release_names = extract_release_names(changeset.releases)
          if release_filter.any?
            release_names.select! { |release_name| release_filter.include?(release_name) }
          end

          release_names.each do |release_name|
            release_groups[release_name] << changeset
          end
        end

        release_groups
      end

      # Private: Extract release names from a changeset's releases field.
      #
      # The releases field can contain:
      # - Strings: "api.github.com", "ghec"
      # - Hashes: { "ghes" => ">= 3.10" }
      #
      # Returns an Array of String release names.
      def extract_release_names(releases)
        release_names = releases.flat_map do |release|
          case release
          when String
            release
          when Hash
            expand_release_constraint(release)
          end
        end

        release_names.compact.uniq
      end

      # Private: Expand a release constraint hash to matching release identifiers.
      #
      # For example, { "ghes" => ">= 3.10" } expands to ["ghes-3.10", "ghes-3.11", ...]
      #
      # Returns an Array of String release identifiers.
      def expand_release_constraint(release_constraint)
        release_name, version_requirement = release_constraint.first
        requirement = Gem::Requirement.create(version_requirement)

        matching_releases = all_releases.select do |release|
          release.name == release_name &&
            release.version &&
            requirement.satisfied_by?(release.version) &&
            !release.identifier.match?(/99\.99/)
        end

        matching_releases.map(&:identifier)
      end

      # Private: Memoized list of all releases.
      #
      # Returns an Array of Release instances.
      def all_releases
        @all_releases ||= begin
          releases = OpenApi::Description::Release.all(include_unpublished: @include_unpublished_releases)
          releases.select!(&:published?) unless @include_unpublished_releases
          releases
        end
      end

      # Private: Generate a changelog for a specific release.
      #
      # Returns the Pathname of the generated file.
      def generate_for_release(release_name, changesets)
        changesets_by_version = changesets.group_by(&:version)
        sorted_versions = changesets_by_version.keys.sort.reverse

        content = changelog_header(release_name)

        sorted_versions.each do |version|
          sorted_version_changesets = changesets_by_version[version].sort_by(&:created_at)
          content << format_version_section(version, sorted_version_changesets)
        end

        release_dir = @output_dir.join(release_name).tap(&:mkpath)
        changelog_path = release_dir.join("CHANGELOG.md")
        changelog_path.write(content)

        changelog_path
      end

      # Private: Format a version section of the changelog.
      #
      # Returns a String of markdown.
      def format_version_section(version, changesets)
        section = "## Version #{version}\n\n"

        changesets.each do |changeset|
          section << format_changeset(changeset)
        end

        section << "\n"
        section
      end

      # Private: Format a single changeset entry.
      #
      # Returns a String of markdown.
      def format_changeset(changeset)
        description = changeset.description.chomp(".")
        entry = "- **#{description}**\n"

        if changeset.notes.present?
          notes_lines = changeset.notes.strip.split("\n")
          notes_lines.each { |line| entry << (line.empty? ? "\n" : "  #{line}\n") }
        end

        endpoints = changeset.affected_endpoints
        if endpoints.present?
          entry << "\n  <details>\n"
          entry << "  <summary><strong>Affected endpoints</strong></summary>\n\n"
          endpoints.each { |ep| entry << "  - `#{ep}`\n" }
          entry << "\n  </details>\n\n"
        end

        entry
      end
    end
  end
end
