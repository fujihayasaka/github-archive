# typed: true
# frozen_string_literal: true

module Codespaces
  class VscsServiceStampAvailability
    include GitHub::Memoizer

    attr_reader :stamp

    def initialize(stamp)
      @stamp = stamp
    end

    def available?(user:)
      available_for_creates?(user:) && available_for_resumes?(user:)
    end

    def available_to?(user:)
      # In development our default vscs_target is :development which is in turn marked as :internal. Without this
      # ENV check we'd require all users in development to have the codespaces_developer flag which feels weird
      # and unnecessary.
      return true if Rails.env.development?

      # codespaces_developer is an escape hatch for staff/testing to access any stamp
      return true if user.feature_flag_enabled?(:codespaces_developer, default: false)

      # WHERE: available_in controls which instances this stamp is available on.
      # When present, the current instance must be in the list.
      # When absent/empty, there is no instance restriction (available everywhere).
      return false if stamp.available_in.present? && !available_in_current_instance?

      # WHO: ga?/internal controls which users can access this stamp.
      # GA stamps are available to all users; internal stamps require codespaces_developer.
      stamp.ga?
    end

    def available_for_creates?(user:)
      return false unless available_to?(user:)

      # These flags are intended for staff-ship only, to allow testing regions that are
      # flagged to be generally rejected below.
      return true if FeatureFlag.vexi.enabled_or_raise?(override_flag_name, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      return false if FeatureFlag.vexi.enabled_or_raise?(reject_creates_flag_name, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      # Block codespace creation for users whose email domain matches an actor on the
      # codespaces_block_email_domain flag. This applies globally across all regions.
      # Guarded by codespaces_email_domain_blocking_enabled (default off) so the feature
      # can be rolled out/back independently of actor configuration.
      #
      # On-call mitigation steps:
      #   1. Go to DevPortal → Feature Flags → codespaces_block_email_domain
      #   2. Add an Actor ID in the format "VexiEmailDomain:<domain>", e.g. "VexiEmailDomain:gjrnj.cn"
      #   3. For a user with email "attacker@sub.gjrnj.cn", actors are generated for every
      #      domain suffix: "sub.gjrnj.cn", "gjrnj.cn", "cn". If any matches an actor on the
      #      flag, the user is blocked. So "VexiEmailDomain:gjrnj.cn" blocks @gjrnj.cn and
      #      all subdomains. To block an entire TLD, use e.g. "VexiEmailDomain:icu".
      if FeatureFlag.vexi.enabled?(email_domain_blocking_enabled_flag_name, default: false)
        domain_actors = GitHub::VexiEmailDomain.actors_for_email(user.email.to_s)
        return false if domain_actors.any? do |actor|
          FeatureFlag.vexi.enabled?(block_email_domain_flag_name, actor, default: false)
        end
      end

      true
    end

    def available_for_resumes?(user:)
      return false unless available_to?(user:)

      # For safety, our feature flags are negative -- if they don't exist then traffic can flow freely.
      return false if FeatureFlag.vexi.enabled_or_raise?(reject_resumes_flag_name, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      if FeatureFlag.vexi.enabled?(email_domain_blocking_enabled_flag_name, default: false)
        domain_actors = GitHub::VexiEmailDomain.actors_for_email(user.email.to_s)
        return false if domain_actors.any? do |actor|
          FeatureFlag.vexi.enabled?(block_email_domain_flag_name, actor, default: false)
        end
      end

      true
    end

    def percent_available_for_creates
      100 - FeatureFlag.vexi.percentage_of_actors_value_or_raise(reject_creates_flag_name).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    end

    def percent_available_for_resumes
      100 - FeatureFlag.vexi.percentage_of_actors_value_or_raise(reject_resumes_flag_name).to_i # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
    end

    def failover(creates: true, resumes: true, percent: 100)
      # Percent allows for partial failover of a region through our chatops without direct FF manipulation
      FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(reject_resumes_flag_name, percent.to_f) if resumes # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
      FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(reject_creates_flag_name, percent.to_f) if creates # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    end

    def failback(creates: true, resumes: true)
      # Apparently failback is the opposite/inverse of failover. Who knew?
      FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(reject_resumes_flag_name, 0.0) if resumes # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
      FeatureFlag.vexi_management.set_feature_flag_percentage_of_actors(reject_creates_flag_name, 0.0) if creates # rubocop:disable GitHub/FeatureManagement/NoVexiManagementUsage
    end

    private

    memoize def region_id
      stamp.region.id.downcase
    end

    memoize def target
      stamp.vscs_target
    end

    # Checks whether the stamp is configured to be available in the current instance
    # (GitHub.com or a specific Proxima stamp).
    # `available_in` lists the instances where this stamp may be used at all (i.e., it
    # controls *where* the stamp can be used), but it does not by itself make the stamp
    # GA or available to all users. Normal user eligibility (the *who*) is enforced by
    # higher-level checks (e.g., `available_to?` / `stamp.ga?` / internal status).
    memoize def available_in_current_instance?
      return false unless stamp.available_in.present?

      current_instance = GitHub::Config::Proxima.current_stamp_or_dotcom

      # In multitenant test mode, HEAVEN_DEPLOYED_ENV may be empty so current_stamp_or_dotcom
      # returns "". We can't restrict by instance when we don't know which instance we're on.
      return true if current_instance.blank?

      stamp.available_in.include?(current_instance)
    end

    def block_email_domain_flag_name
      :codespaces_block_email_domain
    end

    def email_domain_blocking_enabled_flag_name
      :codespaces_email_domain_blocking_enabled
    end

    memoize def override_flag_name
      "codespaces_region_override_rejection_#{region_id}"
    end

    memoize def reject_creates_flag_name
      target_suffix = target == :production ? "" : "_#{target}"
      "codespaces_region_rejecting_creates_#{region_id}#{target_suffix}"
    end

    memoize def reject_resumes_flag_name
      target_suffix = target == :production ? "" : "_#{target}"
      "codespaces_region_rejecting_resumes_#{region_id}#{target_suffix}"
    end
  end
end
