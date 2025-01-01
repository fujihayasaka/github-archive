# typed: strict
# frozen_string_literal: true

module Configurable
  module MaxPackagesAuthorizablePerToken
    extend T::Sig
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "max_packages_authorizable_per_token"

    DEFAULT_LIMIT = 7_500
    HIGHEST_REASONABLE_PACKAGE_COUNT = 30_000

    sig { returns(Integer) }
    def max_packages_authorizable_per_token
      config.get(KEY)&.to_i || DEFAULT_LIMIT
    end

    sig { returns(Integer) }
    def highest_safe_package_count_for_authorization
      HIGHEST_REASONABLE_PACKAGE_COUNT
    end

    sig { params(value: Integer, actor: User).returns(Integer) }
    def set_max_packages_authorizable_per_token(value, actor)
      return max_packages_authorizable_per_token if value < 1 || value > highest_safe_package_count_for_authorization

      config.set!(KEY, value.to_i, actor)
      value.to_i
    end
  end
end
