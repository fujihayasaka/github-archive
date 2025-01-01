# typed: true
# frozen_string_literal: true

class DiscussionTimeline::AuthorRolePreloader
  extend T::Sig

  sig { params(rendered_records: T.untyped, repository: T.untyped).void }
  def initialize(rendered_records:, repository:)
    @rendered_records = rendered_records
    @repository = repository
  end

  sig { params(discussion_or_comment: T.untyped).returns(T.untyped) }
  def action_or_role_level_for(discussion_or_comment)
    load unless loaded?
    @action_or_role_level_by_author_id.fetch(
      discussion_or_comment.user_id,
      Promise.resolve(nil),
    ).sync
  end

  sig { returns(T.untyped) }
  def preload
    load unless loaded?
  end

  private

  attr_reader :rendered_records, :repository

  def loaded?
    !!@action_or_role_level_by_author_id
  end

  def load
    authors = rendered_records.map(&:user).compact.uniq

    authors.each_slice(1000) do |users|
      Repository.preload_repository_permissions(
        repositories: [repository],
        users: users
      )
    end

    author_id_to_async_role = authors.each_with_object({}) do |user, result|
      # We don't want to include employee granted permissions here because
      # this is specifically being used to show/hide badges per-user

      result[user.id] = repository.async_action_or_role_level_for(
        user,
        include_employee_granted_permissions: false,
        include_custom_roles: false
      )
    end

    Promise.all(author_id_to_async_role.values).sync

    @action_or_role_level_by_author_id = author_id_to_async_role
  end
end
