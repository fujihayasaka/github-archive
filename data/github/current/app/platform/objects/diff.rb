# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Diff < Platform::Objects::Base
      description "Represents a diff between two commits objects."

      def initialize(*)
        super
        @context.scoped_merge!(root_commit_arguments: { oid: @object.diff.sha2 })
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.async_owner_if_org(object.base_repo).then do |org|
          permission.access_allowed?(
            :get_diff,
            resource: object.base_repo,
            current_org: org,
            current_repo: object.base_repo,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.base_repo)
      end

      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      field :files_changed, Integer, "The number of files changed in this diff.", method: :changed_files, null: false

      field :lines_added, Integer, "The number of lines added in this diff.", method: :additions, null: false

      field :lines_deleted, Integer, "The number of lines removed in this diff.", method: :deletions, null: false

      field :lines_changed, Integer, "The total lines added or removed in this diff.", method: :changes, null: false

      field :diff_entries, Connections.define(Objects::Patch), description: "The set of entries constituting this diff.", null: false, connection: true, method: :patches, extras: [:lookahead]

      field :patches, Connections.define(Objects::Patch), description: "The set of patches constituting this diff.", null: false, connection: true, extras: [:lookahead]

      def patches(lookahead:)
        ArrayWrapper.new(
          patch_subjects(lookahead:).map { |subject| Models::Patch.new(@object, subject, pull_request: @object.pull_request) }
        )
      end

      field :patch, Objects::Patch, description: "Returns a patch by the given path.", null: true, extras: [:lookahead], required_capabilities: [:mobile_only_schema_mask] do
        argument :path, String, required: true, description: "The path of the patch to return."
      end

      def patch(lookahead:, path:)
        entry_or_delta = patch_subjects(lookahead:).entries.find { |subject| subject.path == path }

        if entry_or_delta.nil?
          raise Platform::Errors::NotFound.new("Could not find a patch with the given path.")
        end

        Models::Patch.new(@object, entry_or_delta)
      end

      field :summary, [Objects::SummaryDelta], description: "Lists the files changed within this pull request.", visibility: :internal, null: true

      def summary
        ArrayWrapper.new(@object.deltas)
      end

      private

      # Patches can come from deltas or entries based on lookahead or role.
      # TODO: bite the bullet and split these up since the semantics are not the same.
      def patch_subjects(lookahead:)
        use_entry_for_patch_subject?(lookahead:) ? @object.entries : @object.deltas
      end

      # TODO the use_entries? method incompletely detects the use of text in
      # subselections, which should be the primary determinant of whether we
      # need entries. Hence the need for these other hacks which just force
      # entries.
      def use_entry_for_patch_subject?(lookahead:)
        (
          Helpers::InternalGraphql.internal_graphql?(context) ||
          Apps::Privileged.capable?(:diff_show_patch_entries, app: context[:oauth_app]) ||
          Helpers::Diff.use_entries?(lookahead)
        )
      end
    end
  end
end
