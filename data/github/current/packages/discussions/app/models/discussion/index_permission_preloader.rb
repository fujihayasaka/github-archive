# typed: true
# frozen_string_literal: true

class Discussion::IndexPermissionPreloader
  extend T::Sig

  sig do
    params(
      repository: T.untyped,
      discussions: T.untyped,
      categories: T.untyped,
      viewer: T.untyped,
      interaction_allowed: T.untyped
    ).returns(T.untyped)
  end
  def self.load_for(repository:, discussions:, categories:, viewer:, interaction_allowed:)
    new(
      repository: repository,
      discussions: discussions,
      categories: categories,
      viewer: viewer,
      interaction_allowed: interaction_allowed,
    ).tap do |preloader|
      # Warm up permissions
      # This will help us see bottlenecks/issues in flamegraphs
      preloader.preload
    end
  end

  sig do
    params(
      repository: T.untyped,
      discussions: T.untyped,
      categories: T.untyped,
      viewer: T.untyped,
      interaction_allowed: T.untyped
    ).void
  end
  def initialize(repository:, discussions:, categories:, viewer:, interaction_allowed:)
    @repository = repository
    @discussions = discussions
    @categories = categories
    @viewer = viewer
    @interaction_allowed = interaction_allowed
  end

  sig { returns(T.untyped) }
  def preload
    return if viewer.nil?

    Promise.all(permissions.values).sync
  end

  # Look up a precomputed permission.
  #
  # action - a Symbol naming the desired action. To see which actions are valid, consult the
  #   `#viewer_permission_promises` method.
  #
  # Returns `true` if this viewer this instance was constructed with can perform the desired action, `false` if not.
  sig { params(action: T.untyped).returns(T.untyped) }
  def can?(action)
    return false if viewer.nil?

    permissions.fetch(action.to_sym).sync
  end

  private

  attr_reader :viewer, :repository, :discussions

  def interaction_allowed?
    @interaction_allowed
  end

  # Collect necessary permissions for the current user and discussions list into a single Promise.
  def permissions
    @_permissions ||= {
      manage_discussion_spotlights: viewer.async_can_manage_discussion_spotlights?(@repository),
      can_toggle_discussions_setting: @repository.async_can_toggle_discussions_setting?(viewer),
      create_discussion: async_can_create_discussion_in_current_categories,
      create_discussion_category: viewer.async_can_create_discussion_category?(@repository),
    }
  end

  def async_can_create_discussion_in_current_categories
    viewer.async_can_create_discussion?(repository, interaction_allowed: interaction_allowed?).then do |can_create_discussion|
      next false unless can_create_discussion

      repo_has_non_announcement_categories = @categories.any? { |category| !category.supports_announcements }
      repo_has_non_announcement_categories || repository.async_can_create_discussion_announcements?(viewer)
    end
  end
end
