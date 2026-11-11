# typed: true
# frozen_string_literal: true

class RepositorySearchShortcut < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::Prioritizable
  include GitHub::Validations
  include Instrumentation::Model
  include SearchDisplayable
  include SearchQueryable
  include Repositories::BelongsToRepository

  MAX_PER_REPOSITORY = 25

  attr_accessor :acting_user
  attr_accessor :creation_source

  belongs_to_repository_via_domain

  belongs_to :creator,
    class_name: "User",
    foreign_key: :creator_id,
    optional: true,
    inverse_of: false

  prioritizable_by subject: :itself, context: :repository

  validate :repository_has_less_than_max_shortcuts, on: :create
  validates :priority, uniqueness: { scope: [:repository_id, :search_type], allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true
    }

  validates :query, bytesize: { maximum: MYSQL_TEXT_FIELD_LIMIT }, unicode: true
  validates :description, bytesize: { maximum: MYSQL_TEXT_FIELD_LIMIT }, unicode: true

  after_create_commit :instrument_create # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_update_commit :instrument_update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_destroy_commit :instrument_destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def scoping_repository_id
    repository_id
  end

  private

  def repository_has_less_than_max_shortcuts
    if self.class.where(repository_id: repository_id).count >= MAX_PER_REPOSITORY
      errors.add(:base, "cannot have more than #{MAX_PER_REPOSITORY} shortcuts")
    end
  end

  def instrument_create
    instrument_lifecycle("create", actor_id: creator_id, source: creation_source)
  end

  def instrument_update
    instrument_lifecycle("update", actor_id: acting_user&.id)
  end

  def instrument_destroy
    instrument_lifecycle("destroy", actor_id: acting_user&.id)
  end

  def instrument_lifecycle(action, actor_id:, source: nil)
    GlobalInstrumenter.instrument("repository_search_shortcut.#{action}", {
      repository_id: repository_id,
      actor_id: actor_id,
      creator_id: creator_id,
      search_type: search_type,
      shortcut_id: self.id,
      pinned: pinned,
      has_description: description.present?,
      source: source,
    })
  end
end
