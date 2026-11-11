# typed: true
# frozen_string_literal: true

class UnbundledSecurityConfiguration < SecurityConfiguration
  sig { returns(SecurityConfiguration) }
  def bundle!
    raise ArgumentError, "Cannot bundle global configurations" if global?

    bundled = T.cast(becomes!(SecurityConfiguration), SecurityConfiguration)

    if code_security_sku_enabled || secret_protection_sku_enabled
      bundled.enable_ghas = true
    end

    # Use nil (not false) to match the DB default for bundled configs.
    # false means "explicitly disabled" and would cause remove_if_possible
    # to detach repos if the config is later unbundled again.
    bundled.code_security_sku_enabled = nil
    bundled.secret_protection_sku_enabled = nil
    bundled.save!

    bundled
  end

  sig { override.returns(T::Boolean) }
  def bundled?
    false
  end
end
