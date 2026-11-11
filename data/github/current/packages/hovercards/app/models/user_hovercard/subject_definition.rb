# typed: true
# frozen_string_literal: true

class UserHovercard
  module SubjectDefinition
    extend ActiveSupport::Concern
    extend T::Helpers

    abstract!

    requires_ancestor { Object }

    # A default implementation of user_hovercard_parent which returns nil
    # as the parent of a given subject.
    #
    # Classes that import this module are expected to re-define user_hovercard_parent
    def user_hovercard_parent
    end

    # Return a single hovercard context (for use in tests)
    def user_hovercard_context_for(user, viewer:, descendant_subjects: [], limit:)
      async_user_hovercard_contexts_for(user, viewer: viewer, descendant_subjects: descendant_subjects, limit: limit).first&.sync
    end

    # Return the first valid context for the given subject
    def async_user_hovercard_contexts_for(user, viewer:, descendant_subjects: [], limit: nil)
      T.unsafe(self.class).user_hovercard_context_definitions.each_with_object([]) do |(name, context_proc), contexts|
        next if limit && limit != name

        GitHub.dogstats.distribution_time("hovercard.context", { tags: ["#{self.class.name}:#{name}"] }) do
          context = instance_exec(user, viewer, descendant_subjects: descendant_subjects, &context_proc) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          contexts << Promise.resolve(context) if context
        end
      end
    end

    class_methods do
      # Define a hovercard context (for use in a model)
      def define_user_hovercard_context(name, context_proc)
        user_hovercard_context_definitions[name] = context_proc
      end

      # Return all context definitions for the given class
      def user_hovercard_context_definitions
        @user_hovercard_context_definitions ||= {}
      end
    end
  end
end
