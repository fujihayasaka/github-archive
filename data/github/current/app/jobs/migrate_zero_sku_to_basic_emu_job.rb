# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class MigrateZeroSKUToBasicEmuJob < ApplicationJob
  schedule interval: 24.hours, condition: -> { false }

  queue_as :migrate_zero_sku_to_basic_emu
  retry_on_dirty_exit

  sig { params(message: String, business: Business).void }
  def log_info(message, business)
    GitHub.logger.info(
      "info.message" => message,
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.business.id" => business.id,
    )
  end

  sig { params(condition: T.proc.returns(T::Boolean), max_attempts: Integer, block: T.proc.void).void }
  def with_retry(condition, max_attempts: 40, &block)
    attempts = 0
    until condition.call || attempts >= max_attempts do
      yield
      attempts += 1
    end
    raise "Condition not met after #{max_attempts} attempts" unless condition.call
  end

  sig { params(business: Business).void }
  def migrate_config_from_organization_config(business)
    business_config = Copilot::Configuration.find_by!(configurable: business)

    copilot_enabled = :enabled

    # this is to ensure CLI is never set to "unconfigured" if that's the value of any of the org configs
    cli = T.let(business_config.cli == "enabled" ? "enabled" : "disabled", T.untyped)
    chat_enabled = T.let(business_config.chat_enabled, T.untyped)
    public_code_suggestions = T.let(business_config.public_code_suggestions, T.untyped)
    mobile_chat = T.let(business_config.mobile_chat, T.untyped)

    log_info("[config] Previous enterprise config: cli #{cli}, chat_enabled #{chat_enabled}, public_code_suggestions #{public_code_suggestions}, mobile_chat #{mobile_chat}", business)

    org_configs = Copilot::Configuration
      .where(configurable_type: "Organization", configurable_id: business.organizations.pluck(:id))
      .each do |org_config|
        log_info("[config] Old org config: cli #{org_config.cli}, chat_enabled #{org_config.chat_enabled}, public_code_suggestions #{org_config.public_code_suggestions}, mobile_chat #{org_config.mobile_chat}", business)

        cli = org_config.cli if org_config.cli == "enabled"

        if chat_enabled != "enabled" && org_config.chat_enabled_configured?
          chat_enabled = org_config.chat_enabled
        end

        if public_code_suggestions != "blocked" && org_config.public_code_suggestions_configured?
          public_code_suggestions = org_config.public_code_suggestions
        end

        if mobile_chat != "enabled"
          mobile_chat = org_config.mobile_chat
        end
      end

    log_info("[config] New enterprise config: cli #{cli}, chat_enabled #{chat_enabled}, public_code_suggestions #{public_code_suggestions}, mobile_chat #{mobile_chat}", business)

    business_config.update(
      copilot_enabled: copilot_enabled,
      cli: cli,
      chat_enabled: chat_enabled,
      public_code_suggestions: public_code_suggestions,
      mobile_chat: mobile_chat,
      # non-ghec enterprises can only ever have a plan type of business
      copilot_plan: "business"
    )
  end

  sig { params(business_slugs: T::Array[String]).void }
  def perform(business_slugs)
    invalid_slugs = business_slugs - Business.where(slug: business_slugs).pluck(:slug)
    raise "Invalid business slugs: #{invalid_slugs}" unless invalid_slugs.empty?

    Business.where(slug: business_slugs).each do |business|
      # Store state before migration
      original_business_member_ids = business.user_accounts.pluck(:user_id)
      original_copilot_seats = []
      original_org_ids = []
      business.organizations.each do |org|
        original_copilot_seats << Copilot::Seat.where(organization_id: org.id)
        original_org_ids << org.id
      end
      original_copilot_seats = original_copilot_seats.flatten.uniq

      GitHub.logger.info(
        "info.message" => "Migrating business to enterprise teams.",
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.business.id" => business.id,
        "gh.organization.id" => original_org_ids,
        "gh.user.id" => original_business_member_ids,
        "gh.copilot.seat.id" => original_copilot_seats.pluck(:id)
      )

      with_write do
        # Enable feature flag on business
        business.enable_feature(:enterprise_teams_migrate_from_cfb)
        with_retry(-> { business.feature_enabled?(:enterprise_teams_migrate_from_cfb) }) do
          log_info("Sleeping 3 seconds while waiting for feature flag to enable", business)
          business.reload
          sleep(3)
        end
        log_info("Enabled feature flag", business)

        # Migrate config
        migrate_config_from_organization_config(business)
        business.reload
        log_info("Migrated config from orgs", business)

        # Migrate to ET
        copilot_business = Copilot::Business.new(business)
        raise "migrate_to_enterprise_teams aborted due to ineligibility" unless copilot_business.migrate_to_enterprise_teams
        business.reload
        log_info("Completed ET migration", business)

        # Wait for all enterprise teams to be created.
        # Creation is fast and should be done close together, but we don't know how many teams should be created. So, wait a bit and check if any exist.
        sleep(3)
        with_retry(-> { business.enterprise_teams.any? }) do
          log_info("Sleeping 3 seconds while waiting for enterprise team to be created", business)
          sleep(3)
        end

        # Verify new ET exists and all original_copilot_seats exist on the team
        et = business.enterprise_teams.last
        raise "Most recent ET is not copilot-licensees" unless et.name.ends_with?("-copilot-licensees")

        all_et_member_ids = business.enterprise_teams.all.flat_map do |et|
          et.member_user_ids
        end.flatten.uniq
        missing_et_members = original_copilot_seats.pluck(:assigned_user_id) - all_et_member_ids - (business.suspended_member_ids || [])
        raise "The following user IDs were not transfered to the ET: #{missing_et_members}" unless missing_et_members.empty?
        log_info("New ET created", business)

        # Verify Copilot SeatAssignment created for the ET, all others were deleted
        org_seat_assignments = Copilot::SeatAssignment.where(organization_id: original_org_ids)
        et_seat_assignment = Copilot::SeatAssignment.where(assignable: et).first
        raise "SeatAssignment IDs #{org_seat_assignments.pluck(:id)} still exists for orgs" unless org_seat_assignments.empty?
        raise "No SeatAssignment found for the ET" if et_seat_assignment.nil?
        log_info("SeatAssignment created for the ET. Org SeatAssignments have been deleted", business)

        # Verify there is a copilot seat for each member of the ET
        seats = Copilot::Seat.where(copilot_seat_assignment_id: et_seat_assignment.id)
        missing_seats = et.member_user_ids - seats.pluck(:assigned_user_id)
        log_info("The following user IDs exist on the ET but were not granted a seat: #{missing_seats}. This may be due to a delayed copilot backfill.", business) unless missing_seats.empty?
        log_info("Finished transferring seats", business)

        # Verify the old org was deleted
        # This happens async and can take some time, so we wait
        with_retry(-> { business.organizations.empty? }) do
          log_info("Sleeping 3 seconds while waiting for orgs to finish deleting in the background", business)
          sleep(3)
          business.reload
        end

        # Change plan type
        sleep(4)
        with_retry(-> { business.seats_plan_type == "basic" }) do
          business.transition_to_seats_plan_type("basic")
          business.reload

          log_info("Sleeping 3 seconds while trying to transition seats plan type", business)
          sleep(3)
        end
        business.reload

        # Verify no change to enterprise memberships
        business_user_ids = business.user_accounts.pluck(:user_id)
        missing_enterprise_members = original_business_member_ids - business_user_ids
        extra_enterprise_members = business_user_ids - original_business_member_ids
        raise "The following user IDs were removed from the enterprise: #{missing_enterprise_members}" unless missing_enterprise_members.empty?
        raise "The following user IDs were added to the enterprise: #{extra_enterprise_members}" unless extra_enterprise_members.empty?

        business.disable_feature(:enterprise_teams_migrate_from_cfb)
        log_info("Sanity checks passed! Migration complete", business)
      end
    end
  end
end
