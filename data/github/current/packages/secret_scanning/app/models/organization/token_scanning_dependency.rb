# typed: strict
# frozen_string_literal: true

module Organization::TokenScanningDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Organization }

  PUSH_PROTECTION_CUSTOM_MSG_KEY = "push-protection-custom-message"

  sig { returns(T.nilable(String)) }
  def get_push_protection_custom_message
    if config.inherited?(PUSH_PROTECTION_CUSTOM_MSG_KEY)
      return nil
    end
    config.get(PUSH_PROTECTION_CUSTOM_MSG_KEY)
  end

  sig { params(msg: T.nilable(String), updater: User).returns(T::Boolean) }
  def set_push_protection_custom_message(msg, updater)
    config.set(PUSH_PROTECTION_CUSTOM_MSG_KEY, msg, updater)
  end
end
