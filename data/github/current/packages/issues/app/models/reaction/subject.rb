# typed: true
# frozen_string_literal: true

# Public: A mixin to use on any ActiveRecord model that can have Reactions
# attached to it.
module Reaction::Subject
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Kernel }

  def reactable?
    true
  end

  # Public: Returns a subclass of type User for the entity that can allow or disallow reactions in
  # the given context.
  #
  # Example return:
  #
  # #<Organization id: 1>
  #
  # Returns a User
  def reaction_admin
    not_implemented!(__method__)
  end

  # Public: Returns a Promise that resolves to the value returned by `reaction_admin`.
  #
  # Example return:
  #
  # #<Promise @value=#<Organization id: 1>>
  #
  # Returns a Promise
  def async_reaction_admin
    not_implemented!(__method__)
  end

  # Public: Returns a path under which the reactions are scoped for access control checks and routing
  #
  # Example return:
  #
  # /some/repo/reactions
  #
  # Returns a URL path
  def reaction_path
    not_implemented!(__method__)
  end

  # Public: Returns a Promise that resolves to the value returned by `reaction_path`.
  #
  # Example return:
  #
  # #<Promise @value="/some/repo/reactions">
  #
  # Returns a Promise
  def async_reaction_path
    not_implemented!(__method__)
  end

  # Public: Whether or not the given user is authorized to read this object.
  #
  # This method is also implented by other interfaces (e.g. Ability::Subject), so it is possible
  # that it is already implemented in the target class.
  #
  # Returns a Boolean
  def readable_by?(user)
    not_implemented!(__method__)
  end

  # Public: Push reaction to web socket channel subscribers for live update.
  #
  # This behaviour is not necessary, so we make it a no-op by default.
  #
  # Returns nothing.
  def notify_socket_subscribers
  end

  # Public: Get all the reactions on this subject, grouped by their content,
  # and ordered their creation date (the group containing the most recent
  # reaction comes first, etc).
  #
  # Example return:
  #
  # [
  #   ["frowning", [#<Reaction id: 5>, #<Reaction id: 2>]],
  #   ["smile", [#<Reaction id: 4>]]
  # ]
  #
  # Returns an Array.
  def grouped_reactions
    T.unsafe(self).reactions.group_by(&:emotion).reject { |emotion, _| emotion.nil? }.sort_by { |_, r| r.min_by(&:created_at) }
  end

  # Public: Get the reaction counts for a given subject.
  #
  # Example return:
  #
  # {
  #   "frowning" => 2,
  #   "smile" => 1
  # }
  #
  # Returns a Hash
  def reactions_count
    @reactions_count ||= grouped_reactions.map { |k, reactions| [k.content, reactions.length] }.to_h
  end
  attr_writer :reactions_count

  # Public: Know if this subject has a given reaction from a given user
  #
  # Returns a Boolean.
  def reaction_exists?(user:, emotion:)
    return false if user.nil?

    T.unsafe(self).reactions.any? { |reaction| reaction.user_id == user.id && reaction.emotion == emotion }
  end

  def react(actor:, content:)
    Reaction.react(user: actor, subject_id: T.unsafe(self).id, subject_type: self.class.name.demodulize, content: content)
  end

  def unreact(actor:, content:)
    Reaction.unreact(user: actor, subject_id: T.unsafe(self).id, subject_type: self.class.name.demodulize, content: content)
  end

  def async_locked_for?(actor)
    Reaction.async_subject_unlocked?(actor, self).then { |unlocked| !unlocked }
  end

  def async_reactions_locked_for?(actor)
    async_locked_for?(actor)
  end

  private

  def not_implemented!(calling_method)
    raise NotImplementedError.new(
      "A Reaction::Subject must implement a :#{calling_method} method. " +
      "Consider mixing in a Reaction::Subject::* concern.")
  end
end
