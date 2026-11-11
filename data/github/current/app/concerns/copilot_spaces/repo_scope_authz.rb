# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module RepoScopeAuthz
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { Api::App }

    sig { params(space: CopilotSpace).void }
    def enforce_repo_scope_for_space!(space)
      return if CopilotSpaces::RepoScopeFilter.authorized?(space: space, viewer: current_user)

      deliver_error!(404)
    end

    sig { params(target: T.untyped, repository_ids: T::Array[Integer]).void }
    def enforce_repo_scope_for_repository_ids!(target:, repository_ids:)
      return if CopilotSpaces::RepoScopeFilter.authorized_for_repository_ids?(
        repository_ids: repository_ids,
        target: target,
        viewer: current_user,
      )

      deliver_error!(404)
    end

    sig do
      params(
        target: T.untyped,
        resources_attributes: T.nilable(T::Array[T.untyped]),
      ).void
    end
    def enforce_repo_scope_for_submitted_resources!(target:, resources_attributes:)
      return if resources_attributes.blank?

      repository_ids = T.let([], T::Array[Integer])
      resources_attributes.each do |entry|
        next unless entry.is_a?(Hash)
        next if entry[:_destroy] || entry["_destroy"]

        resource_type = (entry[:resource_type] || entry["resource_type"]).to_s
        next unless CopilotSpace::REPO_BACKED_RESOURCE_TYPES.include?(resource_type)

        metadata = entry[:metadata] || entry["metadata"]
        next unless metadata.is_a?(Hash)

        repository_id = metadata[:repository_id] || metadata["repository_id"]
        next if repository_id.blank?

        parsed_id = Integer(repository_id, exception: false)
        next if parsed_id.nil?

        repository_ids << parsed_id
      end

      enforce_repo_scope_for_repository_ids!(target: target, repository_ids: repository_ids.uniq)
    end

    # Filtered in SQL so cursor pagination stays correct: post-LIMIT filtering
    # can hide accessible spaces behind a dense run of denied ones.
    sig do
      params(
        scope: T.untyped,
        target: T.untyped,
      ).returns(T.untyped)
    end
    def apply_repo_scope_filter_to_scope(scope, target:)
      return scope unless FeatureFlag.vexi.enabled?(:copilot_spaces_granular_repo_scope_check, current_user, default: false)
      return scope unless ProgrammaticActor::RepositoryFilter.applicable?(current_user)

      # Materialize the page of candidate space ids once so we don't re-evaluate
      # the (potentially joined) visibility scope as a subquery for each of the
      # two CopilotSpaceResource lookups below.
      space_ids = scope.pluck(:id)
      return scope if space_ids.empty?

      candidate_repo_ids = CopilotSpaceResource
        .where(custom_copilot_id: space_ids)
        .where(resource_type: CopilotSpace::REPO_BACKED_RESOURCE_TYPES.to_a)
        .where.not(denormalized_repository_id: nil)
        .distinct
        .pluck(:denormalized_repository_id)
      return scope if candidate_repo_ids.empty?

      accessible = ProgrammaticActor::RepositoryFilter.perform(
        actor: current_user,
        target: target,
        repository_ids: candidate_repo_ids,
      )
      denied_repo_ids = candidate_repo_ids - accessible
      return scope if denied_repo_ids.empty?

      denied_space_ids = CopilotSpaceResource
        .where(custom_copilot_id: space_ids)
        .where(resource_type: CopilotSpace::REPO_BACKED_RESOURCE_TYPES.to_a)
        .where(denormalized_repository_id: denied_repo_ids)
        .distinct
        .pluck(:custom_copilot_id)
      return scope if denied_space_ids.empty?

      scope.where.not(id: denied_space_ids)
    end
  end
end
