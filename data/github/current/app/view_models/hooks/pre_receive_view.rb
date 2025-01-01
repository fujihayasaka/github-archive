# typed: true
# frozen_string_literal: true

module Hooks
  class PreReceiveView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

    attr_reader :parent, :enabled_final_hooks, :enabled_configurable_hooks, :disabled_configurable_hooks

    def initialize(options)
      super(options)

      @enabled_final_hooks = pre_receive_hooks.select do |hook|
        (hook.enforcement == GitHub::PreReceiveHookEntry::ENABLED) && (hook.final? && hook.hookable_type != parent.configuration_entry_type)
      end

      @enabled_configurable_hooks = pre_receive_hooks.select do |hook|
        (hook.enforcement == GitHub::PreReceiveHookEntry::ENABLED) && (!hook.final? || (hook.hookable_type == parent.configuration_entry_type))
      end

      @disabled_configurable_hooks = pre_receive_hooks.select do |hook|
        (hook.enforcement == GitHub::PreReceiveHookEntry::DISABLED) && (!hook.final? || (hook.hookable_type == parent.configuration_entry_type))
      end
    end

    def final_hook_repository?
      enabled_final_hooks.any? { |hook| hook.hook_repository_exists? }
    end

    private

    def pre_receive_hooks
      @pre_receive_hooks ||= begin
        hooks = {}
        targets = PreReceiveHookTarget
          .for_hookable_and_parents(parent)
          .includes(hook: [:repository])
          .sorted_by("priority")

        targets.each do |target|
          hook_id = target.hook_id
          current = hooks[hook_id]
          next if current && current.final != 0
          hooks[hook_id] = Hooks::PreReceiveItemView.new(
            hook_id,
            target.enforcement_before_type_cast, # expecting the raw value, e.g. 2
            target.final_before_type_cast,
            target.hookable_type,
            target.hook.name,
            parent,
            target.hook.repository.nil? ? 0 : 1,
          )
        end

        hooks.values.sort_by(&:name)
      end
    end
  end
end
