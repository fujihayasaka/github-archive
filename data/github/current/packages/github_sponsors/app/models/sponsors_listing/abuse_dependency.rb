# typed: true
# frozen_string_literal: true

module SponsorsListing::AbuseDependency
  extend ActiveSupport::Concern

  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { SponsorsListing }

  sig { returns T::Boolean }
  memoize def sponsorable_has_received_abuse_report?
    T.must(stafftools_metadata).has_received_abuse_report?
  end

  sig { returns T::Boolean }
  memoize def sponsorable_has_public_non_fork_repository?
    T.must(stafftools_metadata).has_public_non_fork_repository?
  end

  sig { returns T::Boolean }
  def recently_created_github_account?
    T.must(stafftools_metadata).recently_created_github_account?
  end

  sig { returns T::Boolean }
  def sponsorable_github_account_old_enough_for_auto_approval?
    sponsorable_created_at.before?(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago)
  end

  sig { returns T::Boolean }
  def sponsorable_young_enough_for_auto_ban?
    sponsorable_created_at.after?(SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN.ago)
  end

  sig { returns T::Boolean }
  memoize def sponsorable_has_customized_user_profile?
    T.must(stafftools_metadata).has_customized_user_profile?
  end

  sig { returns T::Boolean }
  memoize def supported_country_of_residence?
    Billing::StripeConnect::Account.supported_countries.include?(country_of_residence)
  end

  sig { returns T::Boolean }
  memoize def sponsorable_has_supported_timezone?
    supported_time_zone_names = Sponsors::TimeZone.supported_names
    canonical_timezone = sponsorable_time_zone_name ? ActiveSupport::TimeZone.find_tzinfo(sponsorable_time_zone_name).canonical_identifier : nil
    supported_time_zone_names.include?(canonical_timezone)
  end

  sig { returns T::Boolean }
  memoize def sponsorable_timezone_matches_country_of_residence?
    target_time_zone = sponsorable_time_zone_name.presence
    if target_time_zone && country_of_residence.present?
      Sponsors::TimeZone.names(country_code: country_of_residence).include?(target_time_zone)
    else
      # If both the time zone and country are missing, then they match:
      target_time_zone.nil? && country_of_residence.blank?
    end
  end

  sig { returns ActiveSupport::TimeWithZone }
  memoize def sponsorable_created_at
    sponsorable_created_at = if association(:sponsorable).loaded?
      T.must(sponsorable).created_at
    else
      T.must(stafftools_metadata).sponsorable_created_at
    end
    T.must(sponsorable_created_at)
  end
end
