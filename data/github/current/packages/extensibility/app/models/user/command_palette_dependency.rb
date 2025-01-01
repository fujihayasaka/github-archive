# typed: true
# frozen_string_literal: true

module User::CommandPaletteDependency
  extend T::Helpers

  requires_ancestor { User }

  # Public: Check if the command palette is enabled for the user.
  #
  # Returns Boolean
  def command_palette_enabled?
    return @command_palette_enabled if defined?(@command_palette_enabled)

    # the flipper feature is checked first to prevent additional db queries when unnecessary,
    # as this feature is checked from the global site header on virtually every page.
    @command_palette_enabled = self.feature_enabled?(:command_palette, memoize: false) && feature_preview_enabled?(:command_palette)
  end

  def commands_provider_enabled?
    return @commands_provider_enabled if defined?(@commands_provider_enabled)
    @commands_provider_enabled = self.feature_enabled?(:command_palette_commands, memoize: false)
  end
end
