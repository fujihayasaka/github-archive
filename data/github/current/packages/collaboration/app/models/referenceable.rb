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
end
