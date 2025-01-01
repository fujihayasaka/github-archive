# typed: true
# frozen_string_literal: true

module OpenApi
  module Description
    class BreakingChanges

      BREAKING_KEY = "x-github-breaking-changes"
      # Scope [Symbol] the scope implies the extent to which breaking changes are applied when building the OpenAPI description
      #   :partial - retains `x-github-breaking-changes` with changesets that meet the release constraint
      #   :full - fully applies changesets that meet the release constraint and are active for the given API version then removes `x-github-breaking-changes`
      SCOPES = %i{full partial}.freeze

      # Find file locations for breaking changes associated with a given changeset
      # @changeset [String] the name of a changeset
      #
      # Returns an [Array<String>] of file locations
      def self.find(changeset)
        OpenApi.root.glob("**/*.yaml").each.with_object([]) do |file, found|
          desc = YAML.safe_load(File.read(file))
          if breaking_changes = desc[BREAKING_KEY]
            found << file.to_s if breaking_changes.detect { |c| c["changeset"] == changeset }
          end
        end
      end

      # Public: Apply overlays of breaking changes for a corresponding changeset
      # in an OpenAPI description node (Hash)
      #
      # Returns the same node (Hash); it has been modified in-place.
      def self.apply(node, release: OpenApi.release, api_version:, changeset_schedule: nil, scope:, include_next: true)
        breaking_changes = node[BREAKING_KEY]
        return node if !breaking_changes
        return node if !SCOPES.include?(scope)

        if changeset_schedule.nil?
          changeset_schedule = OpenApi::Description::Changeset.schedule
        end

        inactive_changes = []
        # Node low-level overlay on breaking changes patch
        breaking_changes.map do |change|
          # Un-promoted changesets (in next) will be excluded from the public rest-api-description
          # So we remove changesets in `next` from being documented publicly if include_next=false.
          if changeset_schedule.changeset_version(changeset: change["changeset"]) == :next && !include_next
            inactive_changes << change
            next
          end
          # Apply overlay for the active changeset
          if changeset_schedule.changeset_active?(release: release, version: api_version, changeset: change["changeset"])
            # this is only for the case where there are nested overlays within a patch:
            if change["patch"].is_a?(Array)
              change["patch"].each { |p| OpenApi::Description::Overlay.apply(p, release) }
            else
              OpenApi::Description::Overlay.apply(change["patch"], release)
            end
            # This is only for release specific partial overlays (e.g api.github.com, ghes)
          elsif changeset_schedule.meets_release_constraint?(release: release, changeset: change["changeset"]) && api_version.nil? && scope == :partial
            if change["patch"].is_a?(Array)
              change["patch"].each { |p| OpenApi::Description::Overlay.apply(p, release) }
            else
              OpenApi::Description::Overlay.apply(change["patch"], release)
            end
            change["version"] = changeset_schedule.changeset_version(changeset: change["changeset"]).to_s
          else
            inactive_changes << change
          end
        end

        # reject inactive changes from the node
        breaking_changes.reject! { |c| inactive_changes.include?(c) }

        if scope == :full
          node.delete(BREAKING_KEY)

          # Node top-level breaking changes patch
          breaking_changes.map do |change|
            # Apply change if API version is active for the given changeset
            if changeset_schedule.changeset_active?(release: release, version: api_version, changeset: change["changeset"])
              # this is what handles the main patch: replacement for breaking changes in x-github-breaking-changes
              if change["patch"].is_a?(Array) || change["patch"].key?("op")
                Hana::Patch.new(Array(change["patch"])).apply(node)
              else
                OpenApi::Description::MergingPatch.new(change["patch"]).apply(node)
              end
            end
          end
        end

        if breaking_changes.empty?
          node.delete(BREAKING_KEY)
        end
        node
      end
    end
  end
end
