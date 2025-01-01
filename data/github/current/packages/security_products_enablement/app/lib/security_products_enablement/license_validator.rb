# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class LicenseValidator
    include GitHub::Memoizer

    sig { returns(::Repository) }
    attr_reader :repository

    sig { returns(User) }
    attr_reader :repository_owner

    sig { returns(T::Set[GitHub::Turboghas::SKU]) }
    attr_reader :prevent_additional_sku_usage

    sig do
      params(
        repository: ::Repository,
        repository_owner: User,
        prevent_additional_sku_usage: T.nilable(T::Array[GitHub::Turboghas::SKU])
      ).void
    end
    def initialize(repository, repository_owner, prevent_additional_sku_usage)
      @repository = repository
      @repository_owner = repository_owner
      @prevent_additional_sku_usage = T.let(Set.new(prevent_additional_sku_usage), T::Set[GitHub::Turboghas::SKU])
    end

    # Returns true if the SKU can be enabled for the repository OR if the SKU is already enabled.
    sig { params(sku: GitHub::Turboghas::SKU).returns(T::Boolean) }
    def can_enable_sku?(sku:)
      return false unless sku_needed?

      reason_restricted_from_enabling(sku: sku).nil?
    end

    sig { returns(T::Boolean) }
    def sku_needed?
      return false if repository.public? && !GitHub.enterprise?
      return false unless repository_owner.organization?

      true
    end

    sig { params(sku: GitHub::Turboghas::SKU).returns(T::Boolean) }
    def skip_enabling_sku_features?(sku:)
      return false if repository.public? && !GitHub.enterprise?

      reason_restricted_from_enabling(sku: sku).present?
    end

    sig { params(sku: GitHub::Turboghas::SKU).returns(T.nilable(FailureReason)) }
    def reason_restricted_from_enabling(sku:)
      case sku
      when GitHub::Turboghas::SKU::Bundled
        bundled_advanced_security_restriction_reason
      when GitHub::Turboghas::SKU::CodeSecurity
        code_security_restriction_reason
      when GitHub::Turboghas::SKU::SecretSecurity
        secret_protection_restriction_reason
      else T.absurd(sku)
      end
    end

    private

    sig { returns(AdvancedSecurityLicense) }
    memoize def bundled_advanced_security
      repository_owner.advanced_security_license
    end

    sig { returns(AdvancedSecurityLicense) }
    memoize def code_security
      repository_owner.code_security
    end

    sig { returns(AdvancedSecurityLicense) }
    memoize def secret_protection
      repository_owner.secret_protection
    end

    sig { returns(T.nilable(BundledFailureReason)) }
    memoize def bundled_advanced_security_restriction_reason
      return nil if repository.advanced_security_enabled?

      # note that we are not using the license interface to match
      # the check in SecurityProduct::AdvancedSecurity
      # The only actual difference is, hopefully, in how we stub tests
      if !repository_owner.advanced_security_purchased?
        return BundledFailureReason.new(:advanced_security_not_purchased)
      end

      if !repository.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL)
        return BundledFailureReason.new(:advanced_security_restricted_by_policy)
      end

      if prevent_additional_sku_usage.include?(GitHub::Turboghas::SKU::Bundled)
        if bundled_advanced_security.allowance_exceeded?
          return BundledFailureReason.new(:advanced_security_would_exceed_limit)
        end

        if bundled_advanced_security.seat_usage_increase_if_enabled_for_repo(repository) > 0
          BundledFailureReason.new(:advanced_security_would_exceed_limit)
        end
      end
    end

    sig { returns(T.nilable(CodeSecurityFailureReason)) }
    memoize def code_security_restriction_reason
      return nil if repository.code_security_enabled?

      if !code_security.purchased?
        return CodeSecurityFailureReason.new(:code_security_not_purchased)
      end

      if !repository.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY)
        return CodeSecurityFailureReason.new(:code_security_not_allowed_by_policy)
      end

      if prevent_additional_sku_usage.include?(GitHub::Turboghas::SKU::CodeSecurity)
        if code_security.allowance_exceeded?
          return CodeSecurityFailureReason.new(:code_security_would_exceed_limit)
        end

        if code_security.seat_usage_increase_if_enabled_for_repo(repository) > 0
          CodeSecurityFailureReason.new(:code_security_would_exceed_limit)
        end
      end
    end

    sig { returns(T.nilable(SecretProtectionFailureReason)) }
    memoize def secret_protection_restriction_reason
      return nil if SecurityProduct::TokenScanning.new(repository).enabled?

      if !secret_protection.purchased?
        return SecretProtectionFailureReason.new(:secret_protection_not_purchased)
      end

      if !repository.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY)
        return SecretProtectionFailureReason.new(:token_scanning_restricted_by_enablement_policy)
      end

      if prevent_additional_sku_usage.include?(GitHub::Turboghas::SKU::SecretSecurity)
        if secret_protection.allowance_exceeded?
          return SecretProtectionFailureReason.new(:secret_protection_would_exceed_limit)
        end

        if secret_protection.seat_usage_increase_if_enabled_for_repo(repository) > 0
          SecretProtectionFailureReason.new(:secret_protection_would_exceed_limit)
        end
      end
    end
  end
end
