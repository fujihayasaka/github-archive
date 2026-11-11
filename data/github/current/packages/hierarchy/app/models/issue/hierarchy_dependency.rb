# typed: true
# frozen_string_literal: true

# Hierarchy related methods to be mixed into the Issue model
module Issue::HierarchyDependency
  extend ActiveSupport::Concern

  extend T::Helpers
  requires_ancestor { Issue }

  sig { returns(T.nilable(Hierarchy)) }
  def hierarchy
    return unless hierarchy_data = hierarchy_raw
    Hierarchy.new(hierarchy_data)
  end

  sig { returns(T::Boolean) }
  def hierarchy_loaded?
    defined?(@hierarchy_raw) != nil
  end

  sig { returns(T.nilable(::IssuesGraph::Result)) }
  def hierarchy_raw
    return nil unless hierarchy_loaded?

    @hierarchy_raw
  end

  sig do
    params(hierarchy_result: T.nilable(::IssuesGraph::Result))
      .returns(T.nilable(::IssuesGraph::Result))
  end
  def hierarchy_raw=(hierarchy_result)
    @hierarchy_raw = hierarchy_result
  end

  def hierarchy_synced?
    return @hierarchy_synced if defined?(@hierarchy_synced)
    true
  end

  def hierarchy_synced=(synced)
    @hierarchy_synced = synced
  end

  sig { returns T::Boolean }
  def can_add_tasklist?
    owner = repository&.owner
    return false unless owner
    return false unless owner.feature_flag_enabled?(:tasklist_block, default: false)

    hierarchy_data = hierarchy
    return true unless owner.feature_flag_enabled?(:tasklist_block_hard_limits, default: false) && hierarchy_data
    hierarchy_data.tasklist_blocks.count < TasklistBlocks::Limiter::HARD_LIMIT_TASKLISTS_PER_ISSUE
  end

  sig { params(viewer: T.nilable(User)).returns(T.nilable(HierarchyCommands::Result)) }
  def preload_hierarchy(viewer: nil)
    preload_result = HierarchyCommands::Preload.new(
      issue: T.cast(self, Issue),
      repository: T.must(repository),
      owner: T.must(T.must(repository).owner),
      viewer: viewer
    ).call

    # Temporary as we look to replace the issues graph dependency file
    instance_variable_set(:@hierarchy_state, hierarchy_raw&.data)
    preload_result
  end

  sig { returns(T.nilable(ActiveModel::Error)) }
  def ensure_valid_tasklist_blocks
    return unless repository
    return unless FeatureFlag.vexi.enabled?(:tasklist_block_input_validation, T.must(repository).owner, default: false)
    validation_errors = body_result&.tasklist_block_errors&.select { |error| error.is_a?(TasklistBlocks::ValidationError) }
    return unless validation_errors&.any?

    errors.add(:tasklist_blocks, "contain the following errors -- #{
      validation_errors
        .map(&:to_s)
        .join('; ')
    }")
  end

  sig { returns(T.nilable(ActiveModel::Error)) }
  def under_tasklist_blocks_limits
    return unless repository
    return unless FeatureFlag.vexi.enabled?(:tasklist_block_hard_limits, T.must(repository).owner, default: false)
    limit_errors = body_result&.tasklist_block_errors&.select { |error| error.is_a?(TasklistBlocks::LimitError) }
    return unless limit_errors&.any?

    errors.add(:tasklist_blocks, limit_errors.last.to_s)
  end
end
