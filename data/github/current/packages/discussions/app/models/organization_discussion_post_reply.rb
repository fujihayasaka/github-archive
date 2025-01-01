# typed: true
# frozen_string_literal: true

class OrganizationDiscussionPostReply < ApplicationRecord::Collab # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  belongs_to :user
  # rubocop:todo Rails/InverseOf
  belongs_to :discussion_post, class_name: "OrganizationDiscussionPost",
    foreign_key: "organization_discussion_post_id"
  # rubocop:enable Rails/InverseOf

  include OrganizationDiscussionItem

  attr_readonly :number

  before_create :set_number

  sig { params(organization: T.nilable(Organization)).void }
  def organization=(organization)
    discussion_post&.organization = organization
  end

  sig { returns(T.nilable(Organization)) }
  def organization
    discussion_post&.organization
  end

  sig { override.returns(Promise[T.nilable(Organization)]) }
  def async_organization
    async_discussion_post.then do |discussion_post|
      discussion_post&.async_organization
    end
  end

  sig { override.params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_readable_by?(user)
    Promise.resolve(false) unless user
    async_discussion_post.then do |discussion|
      next false unless discussion
      discussion.async_readable_by?(user)
    end
  end

  sig { override.returns(String) }
  def platform_type_name
    "OrganizationDiscussionComment"
  end

  private

  # Does the given actor have write access to org discussions?
  #
  # actor - Either an IntegrationInstallation, Bot or ProgrammaticAccessBot.
  #
  # Returns a Promise of a Boolean.
  sig do
    override.params(
      actor: T.nilable(T.any(IntegrationInstallation, Bot, ProgrammaticAccessBot))
    ).returns(Promise[T::Boolean])
  end
  def async_is_programmatic_actor_with_write_access?(actor)
    Promise.resolve(false) unless actor
    async_discussion_post.then do |discussion|
      next false unless discussion
      discussion.async_is_programmatic_actor_with_write_access?(T.unsafe(actor))
    end
  end

  sig { void }
  def set_number
    Sequence.create(discussion_post) unless Sequence.exists?(discussion_post)
    self.number = Sequence.next(discussion_post)
  end
end
