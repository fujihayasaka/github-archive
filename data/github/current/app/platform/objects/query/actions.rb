# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Actions
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :repository_action_by_slug, Objects::RepositoryAction, description: "Lookup a single GitHub Action by slug.", null: true do
      argument :slug, String, "Select the action that matches this slug.", required: true
    end

    def repository_action_by_slug(**arguments)
      repo_action = ::RepositoryAction.find_by(slug: arguments[:slug])
      @context[:permission].typed_can_see?("RepositoryAction", repo_action).then do |repo_action_readable|
        repo_action if repo_action_readable
      end
    end

    field :repository_action, Objects::RepositoryAction, description: "Lookup a single GitHub Action", null: true do
      argument :id, ID, "Select the action that matches this id.", required: true
    end

    def repository_action(**arguments)
      ::RepositoryAction.find_by(id: arguments[:id])
    end

    field :repository_actions, Connections.define(Objects::RepositoryAction, name: "RepositoryActions", visibility: :internal), visibility: :internal,
      description: "A list of repository actions.", null: true, connection: true do
      argument :featured_only, Boolean, "Select only actions that are currently featured.", default_value: false, visibility: :internal, required: false
      argument :writable_only, Boolean, "Select only actions that the Viewer has write access to.", default_value: false, visibility: :internal, required: false
      argument :public_only, Boolean, "Select only actions that are publicly accessible.", default_value: false, visibility: :internal, required: false
      argument :order_by, Inputs::RepositoryActionOrder, "Ordering options for the returned repository actions.", required: false,
        default_value: { field: "created_at", direction: "DESC" }
      argument :filter_by, Inputs::RepositoryActionFilters, "Return only actions that match all given filters.", visibility: :internal, required: false, default_value: {}
    end

    def repository_actions(**arguments)
      actions = ::RepositoryAction.discoverable
      actions = actions.featured if arguments[:featured_only]

      if arguments[:order_by]
        field = arguments[:order_by][:field]
        direction = arguments[:order_by][:direction]
        actions = actions.order("repository_actions.#{field} #{direction}")
      end

      if arguments[:filter_by]
        if (featured_val = arguments[:filter_by][:featured]).present?
          actions = actions.where(featured: featured_val)
        end

        if (action_name = arguments[:filter_by][:name]).present?
          actions = actions.with_name(action_name)
        end

        if (category_slug = arguments[:filter_by][:category]).present?
          actions = actions.with_category(category_slug)
        end

        if (action_state = arguments[:filter_by][:state]).present?
          actions = actions.with_state(action_state)
        end

        if (owner_name = arguments[:filter_by][:owner]).present?
          actions = actions.owned_by(owner_name)
        end
      end

      actions = if arguments[:public_only] || @context[:viewer].nil?
        actions.joins(:repository).where("repositories.public = TRUE")
      elsif arguments[:writable_only]
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        associated_ids = @context[:viewer].associated_repository_ids(min_action: :write)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        actions.joins(:repository).where("repositories.id IN (?)", associated_ids)
      else
        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        associated_ids = @context[:viewer].associated_repository_ids(min_action: :read)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        actions.joins(:repository).where("repositories.public = TRUE OR repositories.id IN (?)", associated_ids)
      end

      actions
    end
  end
end
