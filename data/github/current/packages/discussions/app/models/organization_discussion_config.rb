# typed: strict
# frozen_string_literal: true

# We've decided to rename the original association from `OrganizationDiscussionRepository` to
# `OrganizationDiscussionConfig`. This makes it more clear that this is a single config object.
class OrganizationDiscussionConfig < ApplicationRecord::Domain::Discussions
  self.table_name = "organization_discussion_repositories"

  include Instrumentation::Model

  belongs_to :organization
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain legacy_return_type: true

  validates :repository, uniqueness: true, presence: true
  validates :organization, uniqueness: true, presence: true

  after_commit :enable_repository_discussions, if: :repository_id_previously_changed?
  after_commit :instrument_creation_event, on: :create
  after_commit :instrument_update_event, on: :update, if: ->(previous_changes) { previous_changes.present? }
  after_destroy_commit :instrument_deletion_event

  # Transient state used to control Hydro events
  sig { returns(T.nilable(User)) }
  attr_accessor :actor

  private

  sig { void }
  def enable_repository_discussions
    return unless this_repo = repository
    return if this_repo.discussions_on?

    enablement_actor = actor || organization
    this_repo.turn_on_discussions(actor: enablement_actor)
  end

  sig { void }
  def instrument_creation_event
    GlobalInstrumenter.instrument "org_discussions",
      organization_id: organization&.id,
      public_repository_id: repository&.id,
      actor_id: actor&.id,
      action: :ORG_DISCUSSION_CREATED
  end

  sig { void }
  def instrument_update_event
    return if !repository_id_previously_changed?

    GlobalInstrumenter.instrument "org_discussions",
      organization_id: organization&.id,
      public_repository_id: repository&.id,
      actor_id: actor&.id,
      action: :ORG_DISCUSSION_UPDATED
  end

  sig { void }
  def instrument_deletion_event
    instrument :destroy

    GlobalInstrumenter.instrument "org_discussions",
      organization_id: organization&.id,
      public_repository_id: repository&.id,
      actor_id: actor&.id,
      action: :ORG_DISCUSSION_DELETED
  end
end
