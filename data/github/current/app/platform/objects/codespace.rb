# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Codespace < Platform::Objects::Base
      minimum_accepted_scopes %w(site_admin)
      visibility :internal
      description "A codespace created by a GitHub user."

      implements_node templates: [[:cds, :id]],
        # TODO: check in with <insert team name here> about this `ready_date`
        as: "CDS", allow_nil_for: [:id], ready_date: Platform::Helpers::GlobalId::COHORT_5 do |codespace|
          { prefix: :cds, id: codespace.id }
        end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      database_id_field
      created_at_field
      updated_at_field

      field :guid, String, description: "The GUID assigned to this codespace.", null: true

      # null: true since repos can be deleted from under codespaces
      field :repository, Repository, description: "The repository used by the codespace.", null: true

      field :owner, Interfaces::RepositoryOwner, description: "The GitHub user who created this codespace.", null: false

      field :billable_owner, Interfaces::RepositoryOwner, description: "The GitHub user responsible for paying for usage of this codespace.", null: false

      field :name, String, description: "The generated friendly name of this codespace.", null: false

      field :last_used_at, Scalars::DateTime, description: "The approximate last time this codespace was used.", null: true

      field :location, String, description: "The initally assigned location of a new codespace.", null: false

      field :state, String, description: "The last known state of the codespace according to GitHub's logic.", null: false

      field :vscs_state, String, description: "The last known state of the codespace according to VSCS logic.", null: false

      field :devcontainer_path, String, description: "The path to the devcontainer.json file in the repository.", null: true

      def vscs_state
        # need to preload owner,repository, & billable owner since `Codespace#environment_data` is overridden to trigger a backfill job
        # when the field is accessed and it isn't set
        Promise.all([object.async_owner, object.async_repository, object.async_billable_owner]).then do |_, _|
          if object.environment_data.nil?
            ::Codespace::VSCS_STATE_UNKNOWN
          else
            object.environment_data.state || ::Codespace::VSCS_STATE_UNKNOWN
          end
        end
      end

      field :sku_name, String, description: "The codespace SKU (maps to the amount of CPU cores, memory, and disk space allocated).", null: false
    end
  end
end
