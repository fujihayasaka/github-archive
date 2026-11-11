# typed: strict
# frozen_string_literal: true

module Business::TokenScanningDependency
  extend T::Helpers

  requires_ancestor { Business }

  PUSH_PROTECTION_CUSTOM_MSG_KEY = "push-protection-custom-message"

  sig { returns(T.nilable(String)) }
  def get_push_protection_custom_message
    config.get(PUSH_PROTECTION_CUSTOM_MSG_KEY)
  end

  sig { params(msg: T.nilable(String), updater: User).returns(T::Boolean) }
  def set_push_protection_custom_message(msg, updater)
    config.set(PUSH_PROTECTION_CUSTOM_MSG_KEY, msg, updater)
  end
end
