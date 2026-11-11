# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class HooksView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :current_context

      def hooks
        @hooks ||= begin
          hooks = if current_context.is_a?(::Repository)
            Hook.hooks_for_target(current_context).ordered.all
          else
            current_context.hooks.ordered.all
          end
          Hook::StatusLoader.load_statuses(hook_records: hooks, parent: current_context)
        end
      end

      def webhooks
        hooks.select(&:webhook?)
      end

      def page_title
        if current_context.is_a?(::Repository)
          "#{current_context.name_with_owner} - Hooks"
        else
          "#{current_context.login} - Hooks"
        end
      end
    end
  end
end
