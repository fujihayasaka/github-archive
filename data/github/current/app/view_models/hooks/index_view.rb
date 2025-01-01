# typed: true
# frozen_string_literal: true

module Hooks
  class IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    # The org or repo the hooks are installed on
    attr_reader :parent

    def hooks
      @hooks ||= begin
        hooks = if parent.is_a?(Repository) && parent.repo_hook_associations_ff?
          Hook.hooks_for_target(parent).ordered.all
        else
          parent.hooks.ordered.all
        end
        if load_hook_statuses?
          Hook::StatusLoader.load_statuses(hook_records: hooks, parent: parent)
        else
          hooks
        end
      end
    end

    def webhooks
      @webhooks ||= hooks.select { |hook| hook.webhook? || hook.cli_hook? }
    end

    def load_hook_statuses
      @load_hook_statuses = true
    end

    def each_with_view(hook_collection)
      hook_collection.each do |hook|
        yield hook, Hooks::ShowView.new(hook: hook, current_user: current_user)
      end
    end

    def repository_context_within_an_organization?
      parent.is_a?(Repository) && parent.owner.organization?
    end

    private

    def load_hook_statuses?
      !!@load_hook_statuses
    end
  end
end
