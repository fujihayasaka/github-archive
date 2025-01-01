# typed: true
# frozen_string_literal: true

module Permissions
  class Enumerator
    # Public: (Enumerator) The actors that have permission to perform action on the
    # subject.
    #
    # Returns an Array of actor IDs.
    def self.actor_ids_with_permission(action:, subject_id:, context: {})
      enumerator = ActionEnumerators.lookup(action: action)
      enumerator.new(subject_id: subject_id, context: context).actor_ids
    end

    # Public: (Enumerator) The subjects the actor have permission to perform the action on
    #
    # Returns an Array of subject IDs.
    def self.subject_ids_for_permission(action:, actor_id:, context: {})
      enumerator = ActionEnumerators.lookup(action: action)
      enumerator.new(actor_id: actor_id, context: context).subject_ids
    end

    attr_reader :subject_id, :actor_id, :context

    def initialize(subject_id: nil, actor_id: nil, context: {})
      @subject_id = subject_id
      @actor_id = actor_id
      @context = context
    end

    def actor_ids
      raise NotImplementedError.new("#actor_ids should be implemented by subclasses")
    end

    def subject_ids
      raise NotImplementedError.new("#subject_ids should be implemented by subclasses")
    end

  end
end
