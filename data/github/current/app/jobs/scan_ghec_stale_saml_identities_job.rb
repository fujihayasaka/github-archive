# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ScanGhecStaleSamlIdentitiesJob < ApplicationJob
  queue_as :scan_ghec_stale_saml_identities

  retry_on_dirty_exit

  # Public: Perform audit or removal (if FF is enabled) of stale external SAML identities.
  #
  # type - "business_provider" or "organization_provider"
  #
  # Returns nothing
  def perform(type)
    log_info("Starting scan_ghec_stale_identities job", type)
    if type == "business_provider"
      perform_stale_saml_identities_for_biz
    elsif type == "organization_provider"
      perform_stale_saml_identities_for_org
    end
  end

  private

  def perform_stale_saml_identities_for_biz
    # retrieve a list of business saml providers active records that are not EMU based
    business_saml_providers = Business::SamlProvider.joins(:target).where("businesses.business_type = 0").includes(:target)
    total_stale_identities_on_all_biz = 0

    business_saml_providers.each do |provider|
      biz = provider.target

      if biz&.feature_flag_enabled_or_raise?(:read_stale_external_identities) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        # find all the external identities for a user that is not disabled or deleted
        # and have a user_id that belongs to the current business' SAML provider

        # selecting empty user_name because user_name is only used for SCIM
        external_identities = ExternalIdentity.by_provider(provider)
          .joins(:user)
          .where(users: { type: "User" })
          .is_active.where(user_name: [nil, ""])

        # find all business user accounts for current business
        business_user_account_ids = BusinessUserAccount.where(business_id: biz.id).pluck(:user_id)
        business_user_account_set = business_user_account_ids.to_set

        # Retrieving the external_identities that do not have a corresponding business user account
        stale_external_id = external_identities.reject do |external_user|
          business_user_account_set.include?(external_user.user_id)
        end
        stale_identities_to_destroy = stale_external_id.map(&:id)

        next unless stale_identities_to_destroy.any?
        total_stale_identities_on_all_biz += stale_identities_to_destroy.count

        log_info("Read stale identities", "business_provider", biz.id,
          false, stale_identities_to_destroy, stale_identities_to_destroy.count)

        if biz.feature_flag_enabled_or_raise?(:delete_stale_external_identities) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          ActiveRecord::Base.connected_to(role: :writing) do
            provider.external_identities.where(id: stale_identities_to_destroy).destroy_all
          end

          log_info("Destroyed stale identities", "business_provider", biz.id,
            true, stale_identities_to_destroy, stale_identities_to_destroy.count)
        end
      end
    end

    log_info("Finished scan_ghec_stale_identities job", "business_provider", nil,
      nil, nil, total_stale_identities_on_all_biz)
  end

  def perform_stale_saml_identities_for_org
    # retrieve a list of org saml providers active records
    org_saml_providers = Organization::SamlProvider.includes(:target)
    total_stale_identities_on_all_orgs = 0

    org_saml_providers.each do |provider|
      org = provider.organization
      # skip orgs that doesn't have an associated business since they're legacy
      next if !org&.business

      if org&.feature_flag_enabled_or_raise?(:read_stale_external_identities) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        # find all the external identities for a user that is not disabled or deleted
        # and have a user_id that belongs to the current org' SAML provider

        # selecting empty user_name because user_name is only used for SCIM
        external_identities = ExternalIdentity.by_provider(provider)
          .joins(:user)
          .where(users: { type: "User" })
          .is_active
          .where(user_name: [nil, ""])

        # find all business user accounts for current business/org
        business_user_account_ids = BusinessUserAccount.where(business_id: org.business&.id).pluck(:user_id)
        business_user_account_set = business_user_account_ids.to_set

        # Retrieving the external_identities that do not have a corresponding business user account
        stale_external_id = external_identities.reject do |external_user|
          business_user_account_set.include?(external_user.user_id)
        end
        stale_identities_to_destroy = stale_external_id.map(&:id)

        next unless stale_identities_to_destroy.any?
        total_stale_identities_on_all_orgs += stale_identities_to_destroy.count

        log_info("Read stale identities", "organization_provider", org.id,
          false, stale_identities_to_destroy, stale_identities_to_destroy.count)

        if org.feature_flag_enabled_or_raise?(:delete_stale_external_identities) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          ActiveRecord::Base.connected_to(role: :writing) do
            provider.external_identities.where(id: stale_identities_to_destroy).destroy_all
          end

          log_info("Destroyed stale identities", "organization_provider", org.id,
            true, stale_identities_to_destroy, stale_identities_to_destroy.count)
        end
      end
    end

    log_info("Finished scan_ghec_stale_identities job", "organization_provider", nil,
      nil, nil, total_stale_identities_on_all_orgs)
  end

  def log_info(message, type, id = nil, flag = nil, stale_identities_id = nil, total_users = nil)
    GitHub.logger.info(
      "info.message" => message,
      "code.namespace" => self.class.name,
      "gh.external_identities.stale_identities_type" => type,
      "gh.external_identities.stale_identities_type_id" => id,
      "gh.external_identities.delete_stale_identities" => flag,
      "gh.external_identities.stale_identities_ids" => stale_identities_id,
      "gh.external_identities.total_stale_identities" => total_users,
    )
  end
end
