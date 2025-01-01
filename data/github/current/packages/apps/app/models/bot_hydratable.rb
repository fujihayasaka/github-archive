# typed: true
# frozen_string_literal: true

module BotHydratable
  extend T::Helpers

  requires_ancestor { Kernel }

  # Public: Returns the Bot with a hydrated ability delegate.
  #
  # Returns a Bot or nothing.
  def bot
    return unless ability_delegate_owner&.bot

    ability_delegate_owner.bot.tap do |b|
      b.ability_delegate = self
    end
  end

  # Internal: Returns the owner of the ability delegate needed for
  # Bot "hydration".
  #
  # Raises an error if not re-defined.
  def ability_delegate_owner
    raise NotImplementedError, "#ability_delegate_owner has not been defined yet"
  end
end
