# typed: strict
# frozen_string_literal: true

# Represents the state of a security product in Quick Setup
class SecurityProductsEnablement::QuickSetupService::State < T::Enum
  enums do
    Enabled = new("enabled")
    Disabled = new("disabled")
    NotSet = new("not_set")
    Custom = new("custom")
  end

  sig { params(value: T.untyped).returns(T.nilable(SecurityProductsEnablement::QuickSetupService::State)) }
  def self.from_enum(value)
    return nil if value.nil?

    deserialize(value.to_s)
  end

  sig { returns(T.nilable(T::Boolean)) }
  def to_security_config_tri_state
    case self
    when Enabled
      true
    when Disabled
      false
    else
      nil
    end
  end
end
