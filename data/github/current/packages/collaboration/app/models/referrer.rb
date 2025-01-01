# typed: true
# frozen_string_literal: true

# When users mention `Referenceable` objects, the context is largely in long
# form Markdown in descriptions and comment bodies. We process that text as
# `GitHub::UserContent` which detects mentions.
module Referrer
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Kernel }
  requires_ancestor { ActiveRecord::Base }

  # Internal: the object that the reference comes from.
  sig { returns Referrer }
  def referrer
    self
  end

  # Internal: the user making the reference.
  sig { returns T.nilable(User) }
  def referring_actor
    return unless respond_to?(:user)
    return T.unsafe(self).user unless self.try(:repository)
    if self.try(:editor).is_a? User
      T.unsafe(self).editor
    else
      T.unsafe(self).user
    end
  end

  # Private: should this comment track references?
  # This is a hook method provided for comments that have
  # more complicated workflow, and may not want to track their references
  # on every single save.
  sig { returns T::Boolean }
  def track_references?
    true
  end
  private :track_references?

  # Creates cross references records via Referenceable#record_reference_from.
  #
  # reference_time - Timestamp used to record when the reference was made.
  #
  # Returns nothing.
  def create_mentioned_references(reference_time)
    Referenceable.batch_record_references_from(mentioned_referenceables, referrer, referring_actor, reference_time)
  end

  # Transient state used to override default behavior, mostly in tests
  attr_accessor :track_references_in_background

  # Should we process the references in a background job?
  sig { returns T::Boolean }
  def track_references_in_background?
    false
  end

  # Internal: Gather all of the `Referenceable` objects that were actually
  # mentioned by this `Referrer`.
  sig { returns T::Array[Referenceable] }
  def mentioned_referenceables
    refs = []

    if respond_to?(:mentioned_teams)
      refs.concat(T.unsafe(self).mentioned_teams.compact)
    end

    if respond_to?(:mentioned_issues)
      refs.concat(T.unsafe(self).mentioned_issues.compact)
    end

    if respond_to?(:mentioned_discussions)
      refs.concat(T.unsafe(self).mentioned_discussions.compact)
    end

    refs
  end

  # Is the `Referenceable` object being imported?
  sig { returns T::Boolean }
  def object_imported?
    respond_to?(:importing?) && T.unsafe(self).importing?
  end

  class_methods do
    extend T::Helpers

    requires_ancestor { T.class_of(ActiveRecord::Base) }

    # Public: Sets up the callbacks for reference mentions.
    sig { void }
    def setup_referrer
      before_save reference_mentions_callback, if: :track_references?, unless: :object_imported?
      after_save reference_mentions_callback, if: -> do
        T.bind(self, Referrer)
        track_references? && !track_references_in_background?
      end, unless: :object_imported?
      after_commit reference_mentions_callback, if: -> do
        T.bind(self, Referrer)
        return unless persisted?

        track_references? && track_references_in_background?
      end, unless: :object_imported?
    end

    sig { returns ReferenceMentionsCallback }
    def reference_mentions_callback
      @reference_mentions_callback ||= ReferenceMentionsCallback.new
    end
  end

  class ReferenceMentionsCallback
    def after_save(referrer)
      track_references!(referrer)
    end

    def after_commit(referrer)
      track_references!(referrer)
    end

    def before_save(referrer)
      @previous_updated_at = referrer.updated_at
    end

    def track_references!(referrer)
      reference_mentions(referrer)

      @previous_updated_at = nil

      true
    end

    # Create references for mentioned referenceables.
    # This is run after save.
    #
    # Returns nothing.
    private def reference_mentions(referrer)
      return unless actor = referrer.referring_actor

      ref_time = reference_time(referrer)

      if GitHub.flipper[:check_reference_exists].enabled?
        return if referrer.mentioned_referenceables.empty?

        source = case referrer.class.to_s
        when "IssueComment"
          referrer.issue
        when "PullRequestReviewComment"
          referrer.issue
        else
          referrer
        end

        return if referrer.mentioned_referenceables.count == 1 &&
          CrossReference.where(source: source, target: referrer.mentioned_referenceables).exists?
      end

      if referrer.track_references_in_background?
        ProcessMentionedReferencesJob.perform_later(referrer, ref_time)
      else
        referrer.create_mentioned_references(ref_time)
      end
    end

    # Internal
    #
    # The reference time is recorded as when the reference itself was made.
    # This means when the referrer was updated (or created) if the body was changed.
    # If the body was *not* changed, use the cached updated_at value from
    # before saving.
    #
    # Returns Time used for reference
    private def reference_time(referrer)
      if referrer.saved_change_to_body?
        referrer.updated_at
      else
        @previous_updated_at
      end
    end
  end
end
