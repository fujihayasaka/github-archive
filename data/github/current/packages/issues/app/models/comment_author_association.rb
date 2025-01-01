# typed: true
# frozen_string_literal: true

class CommentAuthorAssociation < AuthorAssociationBase
  alias :comment :resource
  alias :viewer :user
  def initialize(comment:, viewer:)
    super(resource: comment, user: viewer)
  end

  def mannequin?
    async_mannequin?.sync
  end

  def async_mannequin?
    comment.async_user.then do |user|
      user&.mannequin?
    end
  end

  def member?
    async_member?.sync
  end

  def async_member?
    return Promise.resolve(false) if comment.is_a? GistComment

    comment.async_repository.then do |repository|
      if repository.feature_enabled?(:author_association_internal_repository)
        next false unless repository.public? || repository.internal?
      else
        next false unless repository.public?
      end

      repository.async_organization.then do |organization|
        next false unless organization

        Platform::Loaders::VisibleOrganizationMemberCheck.load(viewer, organization, comment.user_id)
      end
    end
  end

  def owner?
    async_owner?.sync
  end

  def async_repo_owner?
    comment.async_repository.then do |repository|
      repository.async_organization.then do |organization|
        # Only display owner badge for repositories not owned by organizations
        next false if organization

        comment.async_user.then do |user|
          repository.async_adminable_by?(user)
        end
      end
    end
  end

  def async_gist_owner?
    comment.async_gist.then do |gist|
      gist.user_id == comment.user_id
    end
  end

  def async_owner?
    if comment.is_a? GistComment
      async_gist_owner?
    else
      async_repo_owner?
    end
  end

  def collaborator?
    async_collaborator?.sync
  end

  def async_collaborator?
    return Promise.resolve(false) if comment.is_a?(GistComment)

    comment.async_repository.then do |repository|
      next true if repository.owner_id == comment.user_id

      comment.async_user.then do |user|
        repository.async_member?(user)
      end
    end
  end

  def contributor?
    async_contributor?.sync
  end

  def async_contributor?
    return Promise.resolve(false) if comment.is_a?(GistComment)

    Promise.all([comment.async_repository, comment.async_user]).then do |repository, user|
      repository.async_contributor?(user)
    end
  end

  def first_time_contributor?
    async_first_time_contributor?.sync
  end

  def first_timer?
    async_first_timer?.sync
  end

  def async_first_time_contributor?(sitewide: false)
    return Promise.resolve(false) unless viewer
    return Promise.resolve(false) unless comment.is_a?(Issue) || comment.is_a?(PullRequest)
    comment.async_user.then do |user|
      next false if user.is_a?(Bot)

      (comment.is_a?(Issue) ? comment.async_pull_request : Promise.resolve(comment)).then do |pull_request|
        next false if user.is_a?(Bot)
        next false unless pull_request

        comment.async_repository.then do |repository|
          async_viewer_can_see_first_time_contributors?(repository).then do |result|
            next false unless result

            async_contributor?.then do |result|
              next false if result
              async_contributor_pull_request_count(repository: repository, user_id: comment.user_id).then { |count| count > 0 }
            end
          end
        end
      end
    end
  end

  def async_first_timer?
    return Promise.resolve(false) unless viewer
    return Promise.resolve(false) unless comment.is_a?(Issue)

    comment.async_user.then do |user|
      next false if user.is_a?(Bot)

      comment.async_pull_request.then do |pull_request|
        next false unless pull_request

        comment.async_repository.then do |repository|
          async_viewer_can_see_first_time_contributors?(repository).then do |result|
            next false unless result

            async_contributor?.then do |result|
              next false if result
              async_pull_request_count(user).then { |count| count == 1 } if user
            end
          end
        end
      end
    end
  end



  private

  attr_reader :resource
  attr_reader :user

  def async_viewer_can_see_first_time_contributors?(repository)
    if repository.owner_id == viewer.id
      Promise.resolve(true)
    else
      repository.async_owner.then do |owner|
        if owner.organization?
          owner.async_member?(viewer).then do |member|
            next true if member
            repository.async_member?(viewer)
          end
        else
          repository.async_member?(viewer)
        end
      end
    end
  end
end
