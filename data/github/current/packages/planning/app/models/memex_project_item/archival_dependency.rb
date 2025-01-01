# typed: true
# frozen_string_literal: true

module MemexProjectItem::ArchivalDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProjectItem }

  included do
    T.bind(self, T.class_of(MemexProjectItem))

    belongs_to :archiver, class_name: "User"

    scope :archived, -> { where("archived_at > 0") }
    scope :not_archived, -> { where(archived_at: nil) }

    attr_accessor :skip_item_can_be_archived_validation, :bulk_operation

    validate :item_can_be_archived, on: :update, unless: :skip_item_can_be_archived_validation
    validate :has_archiver_if_archived, on: [:create, :update]
  end

  # Update the current item to set the archived_at timestamp to the current
  # time.
  #
  # This will result in the item no longer being shown by default in the
  # project view.
  #
  def mark_as_archived(archiver = nil)
    return if archived?

    archiver ||= actor

    self[:archived_at] = current_time_from_proper_timezone
    self[:archiver_id] = archiver.id
  end

  # items already marked as archived will ignore return without
  # making changes.
  #
  def archive!(archiver = nil, bulk_operation: false)
    return if archived?

    self.bulk_operation = bulk_operation

    archiver ||= actor
    mark_as_archived(archiver)
    save! # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  # Update the current item to clear the archived_at timestamp
  #
  # This will result in the item being visible again in the project view.
  #
  # items not marked as archived will be ignored and return without
  # making changes.
  def unarchive!(bulk_operation: false)
    return unless archived?

    self.bulk_operation = bulk_operation

    update!(archived_at: nil, archiver: nil) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  # Helper method to check whether the item is currently archived
  def archived?
    archived_at.present?
  end

  private

  def item_can_be_archived
    return unless archived?
    return unless (project = memex_project)
    return unless project.would_exceed_limit_to_archive_existing_item?
    errors.add(:base, :archive_limit_reached, limit: project.archived_items_limit)
  end

  def has_archiver_if_archived
    return unless new_record? || archived_at_changed? || archiver_changed?
    return if archived_at.nil? && archiver.nil?
    return if archived_at.present? && archiver.present?

    if archived_at.present?
      errors.add(:archiver, "must be set if archived_at is set")
    else
      errors.add(:archived_at, "must be set if archiver is set")
    end
  end
end
