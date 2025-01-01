# typed: true
# frozen_string_literal: true

# Methods for Advanced Security billing concerns.
# Available on Business, Organization, and User objects.
#
# Doesn't actually store the data but knows how to delegate to the right place
# including for orgs that are part of a business. See `advanced_security_billing_config.rb`
# or the GHES license for the source of the data.
module Configurable
  module AdvancedSecurityBilling
    extend T::Helpers

    requires_ancestor { Configurable }

    include GitHub::Memoizer
    include Kernel

    # Public: Checks if the user has purchased Advanced Security.
    #
    # On GHES, this can be found by looking at the license file.
    # On Cloud:
    # * return false for users; they can't purchase GHAS
    # * for a business-owned org, check if the business has purchased GHAS
    #   and return that, regardless of org-level config
    # * for an "independent" org or a business itself, check the entity-level config
    #
    # Returns Boolean
    def advanced_security_purchased?
      T.bind(self, T.any(User, Organization, Business))

      return GitHub::Enterprise.license.advanced_security_enabled if GitHub.enterprise?
      return if is_a?(Bot) || is_a?(Mannequin)

      case self
      when Business
        advanced_security_purchased_for_entity?
      when Organization
        return business&.advanced_security_purchased_for_entity? if delegate_billing_to_business?
        advanced_security_purchased_for_entity?
      when User
        ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(self)
        ghas_for_users.feature_available?
      end
    end

    memoize def advanced_security_summary
      T.bind(self, T.any(User, Organization, Business))
      AdvancedSecurityLicense.summary(entity: self)
    end

    def advanced_security_seats_used
      T.bind(self, T.any(User, Organization, Business))
      return 0 unless self.advanced_security_purchased?
      advanced_security_summary.active_committers
    end

    def advanced_security_additional_metered_seats_used
      T.bind(self, T.any(User, Organization, Business))
      return 0 unless self.advanced_security_purchased?
      advanced_security_summary.additional_metered_committers
    end

    def advanced_security_business_user_accounts
      return self.class.none unless is_a?(Business)

      user_accounts
        .joins(:enterprise_installation_user_accounts)
        .where(enterprise_installation_user_accounts: { using_advanced_security: true })
    end

    memoize def advanced_security_business_user_ids
      advanced_security_business_user_accounts.where.not(user_id: nil).distinct.pluck(:user_id)
    end

    # Calculates how many extra GHAS seats would be used / contributors would be
    # billed for if GHAS were to be enabled on every repository in this user / org.
    #
    # Returns 0 if GHAS is not purchased.
    memoize def seat_usage_increase_if_advanced_security_enabled_for_all_repos
      T.bind(self, T.any(User, Organization, Business))
      return 0 unless self.advanced_security_purchased?

      GitHub.dogstats.distribution_time("advanced_security_contribution.dist.business_settings_page_enable_all") do
        AdvancedSecurityLicense.seat_usage_increase_if_advanced_security_enabled_for_all_repos(owner: self)
      end
    end

    # If GHAS were to be enabled on all repos, would the GHAS license then be exceeding its seat limit.
    # This includes if the limit is already exceeded.
    def enabling_advanced_security_for_all_repos_would_exceed_seat_allowance?
      T.bind(self, T.any(User, Organization, Business))
      return false unless advanced_security_purchased?
      return false if advanced_security_license.unlimited_seats?

      tags = if self.is_a?(Business)
        {
          "gh.business.id" => id,
          "gh.business.name" => slug
        }
      else
        {
          "gh.org.id" => id,
          "gh.org.login" => display_login
        }
      end

      if advanced_security_license.allowance_exceeded?
        GitHub.logger.info(
          "Enable all seat allowance already exceeded",
          "code.namespace" => self.class.name,
          "code.function" => __method__.to_s,
          **tags,
        )

        return true
      end

      would_exceed_seat_allowance = seat_usage_increase_if_advanced_security_enabled_for_all_repos > advanced_security_license.remaining_seats
      if would_exceed_seat_allowance
        GitHub.logger.info(
          "Enable all will exceed seat allowance",
          "code.namespace" => self.class.name,
          "code.function" => __method__.to_s,
          **tags,
        )
      end

      would_exceed_seat_allowance
    end

    # Public: Is the billable entity for GHAS
    def advanced_security_billable_entity?
      self == advanced_security_billable_entity
    end

    def advanced_security_billable_entity
      advanced_security_license.billable_entity
    end

    # Public: Returns the license object for the current entity.
    sig { returns(AdvancedSecurityLicense) }
    def advanced_security_license
      T.bind(self, T.any(User, Business))
      @advanced_security_license ||= AdvancedSecurityLicense.new(self)
    end
  end
end
