# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module Loops
      # GraphQL object for a Copilot Loop. Internal visibility for now.
      class Loop < Platform::Objects::Base
        visibility :internal
        description "A Copilot Loop"

        # Authorization: loops visible only to owner; hydrate if needed.
        def self.async_api_can_access?(permission, object)
          viewer = permission.viewer
          return false unless viewer.is_a?(::User)

          return true if Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(viewer, self.class.name)

          hydrated = Platform::Loaders::Loops::Loop.load(object.uuid, viewer: viewer)
          return false unless hydrated

          hydrated.owner_id == viewer.id
        end

        def self.async_viewer_can_see?(permission, loop)
          async_api_can_access?(permission, loop)
        end

        # Node loader returns a lightweight placeholder; hydration is lazy.
        def self.load_from_next_global_id(parsed_id)
          uuid = parsed_id.parts[:uuid]
          Promise.resolve(::Loops::Loop.new(uuid: uuid, owner_id: nil, owner_login: nil, title: nil, description: nil))
        end

        def self.use_next_id?(_object)
          true
        end

        # Access hydrated loop via loader (memoized per viewer+uuid)
        sig { returns(T.nilable(::Loops::Loop)) }
        def load_hydrated
          viewer = context[:viewer]
          return nil unless viewer.is_a?(::User)
          Platform::Loaders::Loops::Loop.load(@object.uuid, viewer: viewer)
        end

        # Always-on next IDs via ready_date in the past; UUID is not a database id.
        implements_node templates: [[:lp, :uuid]], as: "LP", ready_date: "2025-11-17", uses_database_id: false do |loop|
          { prefix: :lp, uuid: loop.uuid }
        end

        field :uuid, ID, "Stable identifier for the loop (UUID).", null: false
        field :title, String, "Human-readable title of the loop.", null: true
        field :description, String, "Optional description of the loop.", null: true
        field :version, String, "Version string of the loop definition.", null: true
        field :updated_at, Platform::Scalars::DateTime, "Time the loop was last updated.", null: true
        field :is_shared, Boolean, "Whether the loop is currently shared.", null: false
        field :owner, Unions::Account, "Owner account of the loop.", null: true
        field :internal_nodes_json, String, "Internal-only: raw JSON array of this loop's nodes; not stable and never exposed to end users.", null: true
        field :url, Platform::Scalars::URI, "Web URL for viewing this loop (share URL when shared).", null: true

        def owner
          hydrated = load_hydrated
          owner_id = hydrated&.owner_id || @object.owner_id
          return nil unless owner_id
          Loaders::ActiveRecord.load(::User, owner_id)
        end

        def title
          load_hydrated&.title || @object.title
        end

        def description
          load_hydrated&.description || @object.description
        end

        def version
          load_hydrated&.version || @object.version
        end

        def updated_at
          updated_at = load_hydrated&.updated_at || @object.updated_at
          return nil if updated_at.nil?

          updated_at_str = updated_at.utc.iso8601
          Platform::Scalars::DateTime.coerce_input(updated_at_str, nil)
        end

        def is_shared
          load_hydrated&.visibility == "public"
        end

        def internal_nodes_json
          hydrated = load_hydrated
          nodes = (hydrated.nodes if hydrated) || (@object.respond_to?(:nodes) ? @object.nodes : nil)
          return nil unless nodes
          JSON.generate(nodes)
        end

        def url
          hydrated = load_hydrated || @object
          Platform::Scalars::URI.coerce_isolated_input(GitHub::Migrator::ModelUrlService.new.url_for_model(hydrated))
        end
      end
    end
  end
end
