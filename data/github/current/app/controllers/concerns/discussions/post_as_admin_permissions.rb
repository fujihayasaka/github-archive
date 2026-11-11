# typed: true
# frozen_string_literal: true

module Discussions
  module PostAsAdminPermissions
    extend T::Helpers
    extend ActiveSupport::Concern
    include FeatureFlagHelper

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))

      helper_method :can_post_as_admin?, :can_manage_post_as_admin?, :user_has_repository_admin_access?, :can_view_original_author?
    end

    # Determine whether or not the given user can post a discussion or discussion comment as post as admin for the
    # given repository.
    sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
    def can_post_as_admin?(repository)
      return false unless repository
      return false unless repository.organization_id?
      return false unless repository.public? || repository.org_discussion_source?

      user_has_repository_admin_access?(user: current_user, repository:)
    end

    # This check is different in ensuring that an existing discussion or discussion comment can be managed. Use this
    # when modifying an existing post.
    #
    # In the case the post is already marked as posted as admin, we allow managing it regardless of the original
    # author's access when the current user is an admin this way they can turn off post as admin if they like.
    #
    # However, if the post is not marked as posted as admin, we only allow managing it if the post author
    # has admin access to the repository.
    sig { params(post_as_admin: PostAsAdmin).returns(T::Boolean) }
    def can_manage_post_as_admin?(post_as_admin)
      # Check to see if the current user has admin access to the repository.
      return false unless user_has_repository_admin_access?(user: current_user, repository: post_as_admin.repository)

      # If the post is already marked as posted as admin, allow managing it regardless of the original author's access.
      return true if post_as_admin.post_as_admin?

      # Only allow managing it if the original author has admin access to the repository.
      user_has_repository_admin_access?(user: post_as_admin.user, repository: post_as_admin.repository)
    end

    sig do
      params(
        user: T.nilable(User),
        repository: T.nilable(Repository),
      ).returns(T::Boolean)
    end
    def user_has_repository_admin_access?(user: nil, repository: nil)
      return false unless repository && user
      @_repo_admin_access_cache ||= {}
      cache_key = [repository.id, user.id]
      if @_repo_admin_access_cache.key?(cache_key)
        return @_repo_admin_access_cache[cache_key]
      end
      @_repo_admin_access_cache[cache_key] = repository.adminable_by?(user)
    end

    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment)).returns(T::Boolean) }
    def can_view_original_author?(discussion_or_comment)
      # Do not need to check further if the post is not marked as posted as admin.
      return true unless discussion_or_comment.post_as_admin?

      # Logged out users will never be able to see the original author.
      return false unless (user = current_user)
      return false unless (repository = discussion_or_comment.repository)

      user_has_repository_admin_access?(user:, repository:)
    end
  end
end
