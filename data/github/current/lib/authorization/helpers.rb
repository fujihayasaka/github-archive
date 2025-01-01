# typed: true
# frozen_string_literal: true

module Authorization
  module Helpers

    extend self

    DEFAULT_VALIDATION_MESSAGE = "Invalid query argument"
    VALIDATION_MESSAGES = {
      missing_actor_type: "actor_type required",
      missing_subject_type: "subject_type required",
      missing_actor_ids_or_subject_ids: "subject_ids or actor_ids required",
      missing_subject_ids_or_subject_type: "subject_type or subject_ids required",
      invalid_subject: "Invalid subject %{subject}",
      invalid_actor: "Invalid actor %{actor}",
      invalid_action: "%{action} is not a valid action",
      subject_not_all_same_class: "Subjects are not all the same class.",
      subject_not_acceptable_class: "Subject class '%{klass}' must be of type: %{subject_types}",
    }.freeze

    def valid_actor?(actor)
      actor && actor.actor?
    end

    def valid_subject?(subject)
      subject && subject.subject?
    end

    def valid_action?(action)
      Ability.valid_action?(action)
    end

    def validation_error(key, args = {})
      (VALIDATION_MESSAGES[key.to_sym] || DEFAULT_VALIDATION_MESSAGE) % args
    end
  end
end
