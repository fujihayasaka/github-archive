# typed: true
# frozen_string_literal: true

# WARNING: Improper use of this class may lead to incorrect authorization
# decisions.
#
# This class is intended to be used in one, extremely specific
# situation: Attributing authorship to a "system identity" from _inside_ the
# monolith.
#
# This class must **NEVER** be attached to a User actor or programmatic actor
# accessing the public APIs via api.github.com.
#
# Please see #ce-apps if you have questions.
class AttributionOnlySystemIdentityAbilityDelegate
  include Ability::Participant

  attr_reader :bot
  sig { params(bot: Bot).void }
  def initialize(bot)
    unless Apps::Privileged.capable?(:attribution_only_system_identity, app: bot.integration)
      raise ArgumentError.new("expected linked GitHub App to have the :attribution_only_system_identity capability.")
    end
    @bot = bot
  end

  def id
    nil
  end

  def can?(action, subject)
    subject.permit? self, action
  end

  def permit?(*)
    true
  end

  def async_permit?(*)
    Promise.resolve(permit?)
  end

  def can_have_granular_permissions?
    true
  end
end
