# typed: true
# frozen_string_literal: true
module CommandPalette
  class DialogComponent < ApplicationComponent
    include CommandPaletteHelper
    include SvgHelper

    # Provider order matters when more than 1 provider reports items
    # with the same level of priority.
    PROVIDERS = Providers::Factory::PROVIDERS.values

    LOCAL_PROVIDER_OCTICONS = [
      CommandPalette::Icons::Octicon.new(name: "arrow-right"),
      CommandPalette::Icons::Octicon.new(name: "arrow-right", classes: "color-fg-default"),
      CommandPalette::Icons::Octicon.new(name: "codespaces"),
      CommandPalette::Icons::Octicon.new(name: "copy"),
      CommandPalette::Icons::Octicon.new(name: "dash"),
      CommandPalette::Icons::Octicon.new(name: "file"),
      CommandPalette::Icons::Octicon.new(name: "gear"),
      CommandPalette::Icons::Octicon.new(name: "lock"),
      CommandPalette::Icons::Octicon.new(name: "moon"),
      CommandPalette::Icons::Octicon.new(name: "person"),
      CommandPalette::Icons::Octicon.new(name: "pencil"),
      CommandPalette::Icons::Octicon.issue_open,
      CommandPalette::Icons::Octicon.git_pull_request_draft,
      CommandPalette::Icons::Octicon.new(name: "search"),
      CommandPalette::Icons::Octicon.new(name: "sun"),
      CommandPalette::Icons::Octicon.new(name: "sync"),
      CommandPalette::Icons::Octicon.new(name: "trash"),
      CommandPalette::Icons::Octicon.new(name: "key"),
      CommandPalette::Icons::Octicon.new(name: "comment-discussion"),
      CommandPalette::Icons::Octicon.new(name: "bell"),
      CommandPalette::Icons::Octicon.new(name: "bell-slash"),
      CommandPalette::Icons::Octicon.new(name: "paintbrush"),
    ]

    attr_reader :default_scope, :scope, :staff_bar_enabled, :page_breadcrumb

    def initialize(staff_bar_enabled: false, scope: nil, page_breadcrumb: nil)
      @staff_bar_enabled = staff_bar_enabled
      @scope = scope
      @page_breadcrumb = page_breadcrumb
      @default_scope = page_breadcrumb || scope
    end

    def staff_bar_enabled?
      @staff_bar_enabled
    end

    memoize def context
      Context.new(scope: scope, current_user: current_user)
    end

    def default_scope_id
      default_scope&.global_relay_id
    end

    def default_scope_type
      default_scope&.class&.sti_name
    end

    def search_scoped?
      scope.present?
    end

    def scope_tokens
      return [] unless result_scope
      result_scope.tokens
    end

    def result_scope
      return unless search_scoped?
      @result_scope ||= CommandPalette::ResultScope.new(scope)
    end

    def providers
      PROVIDERS.select { |p| p.enabled?(context) }
    end

    def local_provider_octicons
      LOCAL_PROVIDER_OCTICONS
    end

    def groups
      ResultGroups.all.sort_by(&:sort_order)
    end

    def tip_code_classes
      "p-1 color-bg-subtle rounded-2"
    end

    def tip_classes
      "color-fg-muted f6 px-3 py-1 my-2"
    end

    def default_open?
      params[:command_palette_open]
    end

    def command_query
      params[:command_query]
    end

    def command_mode
      params[:command_mode]
    end

    def provider_path(provider)
      raise TypeError, "Unknown command palette provider identifier: #{provider}" unless CommandPalette::Providers::Factory::PROVIDERS[provider]
      "/command_palette/#{provider}"
    end

    def activation_hotkey
      if logged_in?
        setting_hotkey = current_user.settings.get(:command_palette_open_hotkey)
        return CommandPalette::Hotkey::LEGACY_HOTKEYS.fetch(setting_hotkey, setting_hotkey)
      end

      CommandPalette::Hotkey::DEFAULT_SEARCH_MODE_HOTKEY
    end

    def command_mode_hotkey
      if logged_in?
        setting_hotkey = current_user.settings.get(:command_palette_open_command_mode_hotkey)
        return CommandPalette::Hotkey::LEGACY_HOTKEYS.fetch(setting_hotkey, setting_hotkey)
      end

      CommandPalette::Hotkey::DEFAULT_COMMAND_MODE_HOTKEY
    end

    def clear_keyboard_shortcut
      if is_mac_platform?
        "Meta+Delete"
      else
        "Control+Backspace"
      end
    end

    def is_mac_platform?
      request&.user_agent&.match?(/Macintosh/)
    end
  end
end
