# typed: true # rubocop:todo Sorbet/StrictSigil
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
      Rails.env.development? || stamp.ga? || user.feature_flag_enabled?(:codespaces_developer, default: false)
    end

    def available_for_creates?(user:)
      return false unless available_to?(user:)

      # These flags are intended for staff-ship only, to allow testing regions that are
      # flagged to be generally rejected below.
      return true if FeatureFlag.vexi.enabled_or_raise?(override_flag_name, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      !FeatureFlag.vexi.enabled_or_raise?(reject_creates_flag_name, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    def available_for_resumes?(user:)
      return false unless available_to?(user:)

      # For safety, our feature flags are negative -- if they don't exist then traffic can flow freely.
      !FeatureFlag.vexi.enabled_or_raise?(reject_resumes_flag_name, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
