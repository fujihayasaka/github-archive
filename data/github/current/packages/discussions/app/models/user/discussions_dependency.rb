# typed: true
# frozen_string_literal: true

module User::DiscussionsDependency
  extend T::Helpers
  include FeatureFlagHelper

  requires_ancestor { User }

  # Public: Can this user start a new discussion in the given repository?
  sig { params(repo: Repository).returns(T::Boolean) }
  def can_create_discussion?(repo)
    async_can_create_discussion?(repo).sync
  end

  # Public: Asynchronously determine if this user can start a new discussion in the given repository.
  #
  # repo - the Repository that would own the potential discussion.
  # interaction_allowed - Optionally used to short-circuit the repository interaction check. If `nil`, the interaction
  #   check will be performed asynchronously during this call; if `true` or `false` are specified, the interaction
  #   check will be skipped and the provided value will be used instead.
  #
  # Returns a Promise that resolves to a Boolean.
  sig { params(repo: Repository, interaction_allowed: T.nilable(T::Boolean)).returns(Promise[T::Boolean]) }
  def async_can_create_discussion?(repo, interaction_allowed: nil)
    interaction_allowed_promise = if interaction_allowed.nil?
      User::InteractionAbility.async_interaction_allowed?(user: self, repository: repo)
    else
      Promise.resolve(interaction_allowed)
    end

    Promise.all([
      repo.async_discussion_creation_requires_explicit_permission?,
      interaction_allowed_promise,
    ]).then do |require_explicit_perm, interaction_allowed|
      Platform::Loaders::Permissions::BatchAuthorize.load(
        action: :create_discussion,
        actor: self,
        subject: repo,
        context: {
          "organization.configuration.discussions.requires_explicit_access_for_creation" => require_explicit_perm,
          "subject.repository.interaction_allowed" => interaction_allowed,
        }
      ).then { |decision| decision.allow? }
    end
  end

  # Public: Can this user create discussion categories in the given repository?
  sig { params(repo: Repository).returns(T::Boolean) }
  def can_create_discussion_category?(repo)
    response = ::Permissions::Enforcer.authorize(
      action: :create_discussion_category,
      actor: self,
      subject: repo
    )
    response.allow?
  end

  sig { params(repo: Repository).returns(Promise[T::Boolean]) }
  def async_can_create_discussion_category?(repo)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :create_discussion_category,
      actor: self,
      subject: repo
    ).then { |decision| decision.allow? }
  end

  sig { params(repo: Repository).returns(Promise[T::Boolean]) }
  def async_can_manage_discussion_spotlights?(repo)
    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :manage_discussion_spotlights,
      actor: self,
      subject: repo,
    ).then { |decision| decision.allow? }
  end

  # Public: Does this user have permission to add, remove, and edit
  # discussion spotlights for the given repository?
  sig { params(repo: Repository).returns(T::Boolean) }
  def can_manage_discussion_spotlights?(repo)
    Permissions::Enforcer.authorize(
      action: :manage_discussion_spotlights,
      actor: self,
      subject: repo,
    ).allow?
  end

  # Public: Does this user have permission to add discussion spotlights
  # for the given repository, and the repository isn't already at the limit of
  # how many discussion spotlights it can have?
  sig { params(repo: Repository).returns(T::Boolean) }
  def can_create_discussion_spotlight?(repo)
    return false if DiscussionSpotlight.repository_at_limit?(repo)
    can_manage_discussion_spotlights?(repo)
  end

  sig { params(repo: Repository).returns(T::Boolean) }
  def can_manage_discussion_category_pins?(repo)
    can_manage_discussion_spotlights?(repo)
  end

  # Public: Dismiss the discussions availability announcement shown to this user.
  sig { void }
  def dismiss_discussions_announcement
    Discussions::Kv.store.set("discussion-ann:#{id}", "")
  end

  sig { void }
  def dismiss_private_repo_discussions_announcement
    Discussions::Kv.store.set("discussion-private-repo-ann:#{id}", "")
  end

  # Public: Return true if this user has dismissed the discussions availability announcement.
  sig { returns(T::Boolean) }
  def has_dismissed_discussions_announcement?
    Discussions::Kv.store.mexists(["discussion-ann:#{login}", "discussion-ann:#{id}"]).map { |values| values.any? }.value { true }
  end

  # Public: Return true if this user has dismissed the discussions private repo availability announcement.
  sig { returns(T::Boolean) }
  def has_dismissed_discussions_private_repo_announcement?
    Discussions::Kv.store.exists("discussion-private-repo-ann:#{id}").value { true }
  end

  # Public: Returns discussion comments count that have been marked as answers
  sig { params(viewer: T.nilable(User)).returns(Integer) }
  def discussion_answers_count_visible_to(viewer)
    Platform::Security::RepositoryAccess.with_viewer(viewer) do
      scope = DiscussionComment.preload(:user).filter_spam_for(viewer).chosen_answers
      permission = Platform::Authorization::Permission.new(
        viewer: viewer,
        origin: Platform::ORIGIN_INTERNAL,
      )
      repository_ids_with_authored_discussion_comments = DiscussionComment.
        where(user_id: id).
        distinct.
        pluck(:repository_id)
      filtered_repo_ids = permission.filter_permissible_repository_ids(
        self,
        repository_ids_with_authored_discussion_comments,
        resource: "discussions",
      )

      scope.where(user_id: id, repository_id: filtered_repo_ids).count
    end
  end

  sig { returns(T::Boolean) }
  def opted_out_of_sparkle_votes?
    feature_flag_enabled?(:sparkle_votes_opt_out, default: false)
  end
end
