# typed: true
# frozen_string_literal: true

module Configurable
  module ReadersCanCreateDiscussions
    extend T::Helpers
    extend T::Sig

    include Instrumentation::Model

    requires_ancestor { Configurable }

    KEY = "block_readers_from_creating_discussions"
    DISABLE_ACTION = "disable_reader_discussion_creation_permission"
    ENABLE_ACTION = "enable_reader_discussion_creation_permission"
    CLEAR_ACTION = "clear_reader_discussion_creation_permission"

    # Public: By default, users with read access to repositories can create discussions.
    sig { returns T::Boolean }
    def readers_can_create_discussions?
      !config.enabled?(KEY)
    end

    def allow_readers_to_create_discussions(force: false, actor:)
      changed = if force
        config.disable!(KEY, actor, force)
      else
        config.delete(KEY, actor)
      end

      if changed.present?
        GitHub.dogstats.increment(ENABLE_ACTION)
        instrument(ENABLE_ACTION, instrumentation_payload(actor))
      end
    end

    def block_readers_from_creating_discussions(force: false, actor:)
      changed = config.enable!(KEY, actor, force)

      if changed.present?
        GitHub.dogstats.increment(DISABLE_ACTION)
        instrument(DISABLE_ACTION, instrumentation_payload(actor))
      end
    end

    def clear_block_readers_from_creating_discussions_setting(actor:)
      changed = config.delete(KEY, actor)

      if changed.present?
        GitHub.dogstats.increment(CLEAR_ACTION)
        instrument(CLEAR_ACTION, instrumentation_payload(actor))
      end
    end

    private

    def instrumentation_payload(actor)
      { user: actor, org: self }
    end
  end
end
