# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    # Common helper methods for dealing with Copilot Agent features & CAPI connectivity.
    module Agentic
      COPILOT_AGENT_REPOSITORY_SUGGESTIONS_DEFAULT_LIMIT = 10
      COPILOT_AGENT_REPOSITORY_SUGGESTIONS_CAP_FILTER_BATCH_MULTIPLIER = 5
      COPILOT_AGENT_REPOSITORY_SUGGESTIONS_CAP_FILTER_MAX_ITERATIONS = 10

      # Use this as the main source-of-truth for getting a token you can use for interacting with CAPI.
      sig { returns(Copilot::DecryptedToken) }
      def decrypted_capi_token
        value = @context[:request_token].to_s

        Copilot::DecryptedToken.from(value)
      end

      sig do
        params(
          viewer: User,
          entry_point: Symbol,
          user_session: T.nilable(UserSession),
          request_token_value: T.nilable(String),
          repository: Repository,
        ).returns(Copilot::Token)
      end
      def resolve_copilot_token(viewer:, entry_point:, user_session:, request_token_value:, repository:)
        viewer_using_pat = viewer.using_personal_access_token? || viewer.using_auth_via_user_programmatic_access?
        should_mint = viewer_using_pat && FeatureFlag.vexi.enabled?(:copilot_mint_token_for_api_requests, viewer, default: false)

        if request_token_value.present? && !should_mint
          GitHub.encrypt_and_encode_capi_token(request_token_value)
        else
          CopilotSessions::CopilotApiToken.get_encrypted(
            user: viewer,
            entry_point: entry_point,
            user_session: user_session,
            force_cache_miss: true,
          )
        end
      end

      # Validates bot assignments using the Agentic Apps platform
      sig { params(bots: T::Enumerable[T.untyped], repository: Repository, actor: User).void }
      def validate_agent_bot_assignments!(bots, repository, actor:)
        # Agent assignment is not supported via GitHub App installation tokens
        # (server-to-server). Only user tokens (personal access tokens and OAuth
        # tokens) are permitted. Without this check, the mutation would later
        # fail with the misleading "target repository is not writable" error
        # because installation tokens cannot be checked with `writable_by?`.
        if @context[:permission]&.integration_bot_request?
          Kernel.raise Errors::Forbidden.new(
            "Assigning agents is not supported with GitHub App installation tokens. " \
            "Use a user token (personal access token or OAuth token) instead."
          )
        end

        # Require triage/write access before proceeding — without this check an unprivileged
        # viewer on a public repo could pass a bot node ID and trigger token generation
        # even though the domain layer would later drop the assignment.
        actor_can_assign = repository.pushable_by?(actor) ||
                           repository.resources.issues.writable_by?(actor) ||
                           Issue::PermissionsDependency.triageable_by_user?(actor, repository)
        unless actor_can_assign
          Kernel.raise Errors::Forbidden.new("You must have triage access to assign agents to issues.")
        end

        enabled_agents = AgenticApp.enabled_for_repository(repository, actor)

        if FeatureFlag.vexi.enabled?(:filter_non_assignable_agent_bots, actor, default: false)
          enabled_agent_bots = enabled_agents.select(&:assignable?).map(&:bot_id)
        else
          enabled_agent_bots = enabled_agents.map(&:bot_id)
        end

        # find bots that are not part of the list of enabled_agents
        disabled_bots = bots.reject { |bot| enabled_agent_bots.include?(bot.id) }

        disabled_bots.each do |bot|
          # Check if this bot is an agentic app
          agentic_app = AgenticApp.agent_for_bot_id(bot.id)
          if agentic_app.nil?
            Kernel.raise Errors::Forbidden.new("Bot does not have access to the repository.")
          end

          if !agentic_app.assignable?
            Kernel.raise Errors::Forbidden.new("Bot cannot be assigned to issues or pull requests.")
          end

          Kernel.raise Errors::Forbidden.new("#{agentic_app.display_name} agent is not enabled in this repository.")
        end
      end

      # Builds Copilot agent assignment attributes from mutation input parameters
      sig do
        params(
          agent_assignment: T.untyped,
          repository: Repository,
          remote_ip: T.nilable(String),
          viewer: T.untyped,
          agent_id: T.nilable(Integer)
        ).returns(Issues::AgentAssignmentNewAttributes)
      end
      def get_copilot_attributes(agent_assignment, repository, remote_ip, viewer:, agent_id: nil)
        target_repository = agent_assignment&.target_repository || repository
        base_ref = agent_assignment&.base_ref || repository.default_branch
        custom_instructions = agent_assignment&.custom_instructions

        model = if FeatureFlag.vexi.enabled?(:coding_agent_model_selection, viewer, default: false)
          agent_assignment&.model
        end

        Issues::AgentAssignmentNewAttributes.new(
          target_repository: target_repository,
          base_ref: base_ref,
          custom_instructions: custom_instructions,
          custom_agent: agent_assignment&.custom_agent,
          remote_ip: remote_ip,
          model: model,
          agent_id: agent_id
        )
      end

      # Extracts the IDs for agentic-enabled bots from a collection of actors.
      sig { params(collection: T.untyped).returns(T::Array[Integer]) }
      def agentic_bot_ids_from(collection)
        return [] if collection.nil?

        collection.each_with_object([]) do |actor, ids|
          next unless actor.is_a?(Bot)
          ids << actor.id if AgenticApp.agent_for_bot_id(actor.id)
        end
      end

      # Extracts Copilot SWE bot IDs from a collection of actors.
      sig { params(collection: T.untyped).returns(T::Array[Integer]) }
      def copilot_bot_ids_from(collection)
        return [] if collection.nil?

        collection.each_with_object([]) do |actor, ids|
          next unless actor.is_a?(Bot)
          ids << actor.id if actor.slug == Apps::Privileged::CopilotSWEAgent::SLUG
        end
      end

      private

      sig do
        params(
          viewer: User,
          cap_filter: ::ConditionalAccess::Filter,
          query: String,
          current_repository_id: T.nilable(String),
          limit: Integer,
        ).returns(T::Array[Repository])
      end
      def copilot_agent_repository_suggestions(viewer:, cap_filter:, query:, current_repository_id:, limit:)
        current_repository = copilot_agent_repository_suggestion_from_id(current_repository_id)

        if query.blank?
          top_repositories = copilot_agent_top_repositories(viewer, cap_filter, limit: limit)
          if current_repository&.readable_by?(viewer)
            authorized_repository = cap_filter.authorized_resources([current_repository]).first
            return ([authorized_repository] + top_repositories).compact.uniq(&:id).first(limit)
          end

          return top_repositories
        end

        if query.include?("/")
          owner_login, repository_name = query.downcase.split("/", 2)
          owner = ::User.find_by(login: owner_login)
          return [] unless owner

          return copilot_agent_authorized_repositories_of(
            owner,
            viewer,
            cap_filter,
            repo_name: repository_name || "",
            limit: limit,
          )
        end

        query_downcase = query.downcase
        top_repositories = copilot_agent_top_repositories(viewer, cap_filter, limit: limit)
        ActiveRecord::Associations::Preloader.new(records: top_repositories, associations: :owner).call
        matching_top_repositories = top_repositories.filter do |repository|
          T.must(repository.owner).display_login.downcase.include?(query_downcase) ||
            repository.name.downcase.include?(query_downcase)
        end

        matching_repositories = copilot_agent_authorized_repositories_of(
          viewer,
          viewer,
          cap_filter,
          repo_name: query,
          exclude_ids: matching_top_repositories.map(&:id),
          limit: limit,
        )

        (matching_top_repositories + matching_repositories).uniq(&:id).first(limit)
      end

      sig { params(current_repository_id: T.nilable(String)).returns(T.nilable(Repository)) }
      def copilot_agent_repository_suggestion_from_id(current_repository_id)
        return unless current_repository_id

        Platform::Helpers::NodeIdentification.typed_object_from_id(
          [Platform::Objects::Repository], current_repository_id, @context
        )
      rescue Platform::Errors::NotFound
        nil
      end

      sig { params(viewer: User, cap_filter: ::ConditionalAccess::Filter, limit: Integer).returns(T::Array[Repository]) }
      def copilot_agent_top_repositories(viewer, cap_filter, limit:)
        TopRepositories
          .for(viewer: viewer, since: 1.year.ago, cap_filter: cap_filter)
          .simple_paginate(page: 1, per_page: limit, initial_per_page: limit)
          .to_a
      end

      sig do
        params(
          owner: User,
          viewer: User,
          cap_filter: ::ConditionalAccess::Filter,
          repo_name: String,
          exclude_ids: T::Array[Integer],
          limit: Integer,
        ).returns(T::Array[Repository])
      end
      def copilot_agent_authorized_repositories_of(owner, viewer, cap_filter, repo_name: "", exclude_ids: [], limit: COPILOT_AGENT_REPOSITORY_SUGGESTIONS_DEFAULT_LIMIT)
        permission = Platform::Authorization::Permission.new(viewer: viewer, origin: Platform::ORIGIN_INTERNAL)
        finder = ::Repositories::Public.finder_for(
          owner: owner,
          viewer: viewer,
          permission: permission,
          repo_type: "default",
          unauthorized_viewer_organization_ids: [],
        )

        scope = if owner.is_a?(::Organization)
          T.cast(finder, RepositoriesOrganizationFinder).filter(
            affiliations: [:owned, :direct],
            order_by: { field: :pushed_at, direction: :desc },
          )
        else
          T.cast(finder, RepositoriesFinder).filter(
            affiliations: [:owned, :direct],
            owner_affiliations: [:owned, :direct],
            order_by: { field: :pushed_at, direction: :desc },
          )
        end

        scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
        scope = scope.where("name LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(repo_name)}%")

        authorized_repository_ids = []
        offset = 0

        COPILOT_AGENT_REPOSITORY_SUGGESTIONS_CAP_FILTER_MAX_ITERATIONS.times do
          batch_limit = limit * COPILOT_AGENT_REPOSITORY_SUGGESTIONS_CAP_FILTER_BATCH_MULTIPLIER
          authorized_batch_ids = cap_filter.authorized_resource_ids(scope.limit(batch_limit).offset(offset))
          break if authorized_batch_ids.empty?

          authorized_repository_ids.concat(authorized_batch_ids)
          break if authorized_repository_ids.size >= limit

          offset += batch_limit
        end

        result_ids = authorized_repository_ids.first(limit)
        repositories_by_id = ::Repository.where(id: result_ids).includes(:owner).index_by(&:id)
        result_ids.map { |id| repositories_by_id[id] }.compact
      end

      sig { params(arguments: T::Hash[Symbol, T.untyped], limit: Integer).returns(T::Array[Repository]) }
      def copilot_chat_repository_suggestions(arguments, limit:)
        if arguments[:owner] && arguments[:include_forks]
          Kernel.raise Platform::Errors::ArgumentError, "Cannot specify both owner and include_forks arguments"
        end

        current_repo_db_id = if arguments[:current_repository_id]
          begin
            Helpers::NodeIdentification.typed_object_from_id(
              [Objects::Repository], arguments[:current_repository_id], @context
            )&.id
          rescue Errors::NotFound
            nil
          end
        end

        search = Copilot::Chat::RepositorySearch.new(
          user: @object,
          user_session: nil,
          remote_ip: nil,
          cap_filter: @context[:cap_filter],
        )

        search.search(
          query: arguments[:query] || "",
          limit: limit,
          include_forks: arguments[:include_forks] || false,
          current_repo_id: current_repo_db_id,
          owner: arguments[:owner],
        )
      end
    end
  end
end
