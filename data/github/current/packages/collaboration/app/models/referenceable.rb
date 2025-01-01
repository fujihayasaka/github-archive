# typed: false
# frozen_string_literal: true

# When a thread references another thread, a record is
# created to track that the reference occurred. This lets us display a link to
# the referencing thread from the referenced conversation thread. For
# instance, an Issue comment may reference another Issue via number,
# or it may reference a PullRequest via its number.
#
# The Referenceable mixin is used to mark an object as supporting these types of
# cross references. Associations and methods for tracking and querying references
# are added to the including model.
#
# Models
# ------
#
# Referenceable models include all of the following:
#
#   * Issue
#   * PullRequest
#
# Not all of these have been hooked up yet but you get the idea.
#
module Referenceable
  # Add associations to the including model.
  def self.included(model)
    model.has_many :references,
      class_name: "CrossReference",
      as: :target
  end

  # Record a reference from the source object to self.
  #
  # source - The object that is referencing `self`.
  # actor  - The User that generated the reference.
  # time   - The Time this reference was made
  #
  # Returns the newly created CrossReference record if created
  # successfully or nil when a reference will not be created
  # (because one already exists from the given source or this is
  # self-referential).
  def record_reference_from(source, actor, time)
    if !source.kind_of?(Referrer)
      raise TypeError, "source must be Referrer (#{source.class})"
    end

    return if source == self

    ref = references.build source: source, actor: actor, referenced_at: time

    if ref.save
      try(:notify_socket_subscribers)
      ref
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Record from a batch of references between a source and referancables
  #
  # mentioned_referenceables - Array of referancables to target
  # source                   - The source object
  # actor                    - The User that generated the reference.
  # time                     - The Time this reference was made
  #
  # Returns an ActiveRecord result
  def self.batch_record_references_from(mentioned_referenceables, source, actor, time)
    if !source.kind_of?(Referrer)
      raise TypeError, "source must be Referrer (#{source.class})"
    end

    refs = mentioned_referenceables.map do |ref|
      next if ref == source

      {
        target_id: ref.id,
        target_type: ref.class.to_s,
        target_repository_id: ref.repository_id,
        source_id: source.id,
        source_type: source.class.to_s,
        source_repository_id: source.repository_id,
        actor_id: actor.id,
        referenced_at: time
      }
    end.flatten.compact

    ActiveRecord::Base.connected_to(role: :writing) do
      result = CrossReference.insert_all(refs) unless refs.empty?
      try(:notify_socket_subscribers)
      result
    end
  end
end
