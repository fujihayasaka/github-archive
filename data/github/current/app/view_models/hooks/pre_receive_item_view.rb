# typed: true
# frozen_string_literal: true

module Hooks
  class PreReceiveItemView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    def initialize(hook_id, enforcement, final, hookable_type, name, parent, hook_repository_exists)
      @hook_id = hook_id
      @enforcement = enforcement
      @final = final
      @hookable_type = hookable_type
      @name = name
      @parent = parent
      @hook_repository_exists = hook_repository_exists
    end

    attr_reader :hook_id, :enforcement, :final, :hookable_type, :name, :parent, :hook_repository_exists

    def final?
      final != 0
    end

    def enforcement_label
      if enforcement == GitHub::PreReceiveHookEntry::ENABLED
        "Enabled"
      else
        "Disabled"
      end
    end

    def enforcement_choices
      if parent.is_a?(Repository)
        choices = [
          ["Enabled", GitHub::PreReceiveHookEntry::ENABLED, "Enable this hook on all commits in the #{parent.name} repository.", true],
          ["Disabled", GitHub::PreReceiveHookEntry::DISABLED, "Disable this hook on all commits in the #{parent.name} repository.", true],
        ]
      else
        choices = [
          ["Enabled", GitHub::PreReceiveHookEntry::ENABLED, "Enable your hook on all repositories in the #{parent.name} organization.", true],
          ["Disabled", GitHub::PreReceiveHookEntry::DISABLED, "Disable your hook on all repositories in the #{parent.name} organization.", true],
          ["Configurable (#{enforcement_label})", enforcement, "Allow repository admins to enable/disable per repository. By default, this hook is #{enforcement_label.downcase}.", false],
        ]
      end
    end

    def enforcement_button_label
      if parent.is_a?(Repository)
        enforcement_label
      else
        final? ? enforcement_label : "Configurable (#{enforcement_label})"
      end
    end

    def enforcement_button_value
      enforcement
    end

    def hook_repository_exists?
      hook_repository_exists != 0
    end
  end
end
