# typed: strict
# frozen_string_literal: true

require "vexi"
require "github/flipper_actor"

module FeatureFlagsCommon
  module CustomGates
    extend T::Helpers

    include Kernel

    EMU_MICROSOFT_SHORTCODE = "microsoft"

    EMU_STAGE_1_SHORTCODES = T.let(%w[
      fabrikam
      contoso
      volcano
      fujiv
      cohowine
      emubya
      parnell
      alpine
    ].freeze, T::Array[String])
    EMU_STAGE_3_SHORTCODES = T.let(%w[
      nike
      bxti
      humana
      thdgit
      sasinst
      hmgroup
      icfcorp
      teads
      manh
      SGGIT
      monsec
      nextera
      moto
      citrix
      fedex
      kpmg
      fidelity
      lmigpoc
      tjxinc
      questsw
      tdbank
      reagroup
      avanade].freeze, T::Array[String])
    # The numbers below represent a "percentage" of the businesses.  Assuming that the business ids are
    # evenly distributed the businesses should fall into the groups when id mod 100 is in the range.
    EMU_STAGE_4_SETUP = T.let({
      emu_group_41: 15,
      emu_group_42: 55,
      emu_group_43: 100,
    }.freeze, T::Hash[Symbol, Integer])

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.preview_features(actor)
      actor.respond_to?(:preview_features?) && T.unsafe(actor).preview_features?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.bounty_hunter_target(actor)
      actor.respond_to?(:bounty_hunter_target?) && T.unsafe(actor).bounty_hunter_target?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.maintainers_early_access(actor)
      actor.is_a?(User) && actor.maintainers_early_access?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.integrators_early_access(actor)
      actor.is_a?(User) && actor.integrators_early_access?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor), feature_name: String).returns(T::Boolean) }
    def self.early_access_enabled(actor, feature_name)
      # Account is an alias. We can only type check the actual types in the alias
      # This also works for org because orgs are Users.
      return false unless actor.is_a?(User) || actor.is_a?(Business)
      result = ::GitHub.cache.fetch(EarlyAccessMembership.member_enabled_key(feature_name, actor), ttl: EarlyAccessMembership::FEATURE_CHECK_TTL) do
        [::EarlyAccessMembership.member_enabled?(feature_name, actor)]
      end

      result.first
    end

    #  Adding azure user group for collaborating with GitHub-stacks
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.azure_stacks_collaborators(actor)
      actor.is_a?(User) && actor.azure_stacks_collaborators?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.stacks_contributors(actor)
      actor.is_a?(User) && actor.stacks_contributors?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.microsoft_team_members(actor)
      actor.is_a?(User) && actor.microsoft_everyone_team_access?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.github_stars_members(actor)
      actor.is_a?(User) && actor.github_star?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.shopify_members(actor)
      actor.is_a?(User) && actor.shopify_org?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.microsoft_emu_members(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.shortcode == EMU_MICROSOFT_SHORTCODE
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.shortcode == EMU_MICROSOFT_SHORTCODE
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.shortcode == EMU_MICROSOFT_SHORTCODE
      else
        false
      end
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.microsoft_emu_copilot_members(actor)
      actor.is_a?(User) && actor.org_access?(:'ms-copilot')
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.microsoft_copilot_members(actor)
      actor.is_a?(User) && actor.org_access?(:MicrosoftCopilot)
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.microsoft_mvps(actor)
      actor.is_a?(User) && actor.microsoft_mvp?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.ghec_invoiced_businesses(actor)
      actor.is_a?(Business) && actor.ghec_invoiced_business?
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.developer_relations(actor)
      actor.is_a?(User) && actor.team_access?(:github_developer_relations)
    end

    # A subset of staff owned enterprises or users & organizations for testing purposes.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_stage_1(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.staff_owned? && actor.shortcode.in?(EMU_STAGE_1_SHORTCODES)
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.staff_owned? && actor.business&.shortcode.in?(EMU_STAGE_1_SHORTCODES)
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.staff_owned? &&
        actor.enterprise_managed_business.shortcode.in?(EMU_STAGE_1_SHORTCODES)
      else
        false
      end
    end

    # All new customer enterprises fall in stage-2 by default.
    # Stage-2 = !stage-1 && !stage-3
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_stage_2(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && !actor.shortcode.in?(EMU_STAGE_1_SHORTCODES) && !actor.shortcode.in?(EMU_STAGE_3_SHORTCODES)
      when Organization
        actor.enterprise_managed_user_enabled? && !actor.business&.shortcode.in?(EMU_STAGE_1_SHORTCODES) && !actor.business&.shortcode.in?(EMU_STAGE_3_SHORTCODES)
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        !actor.enterprise_managed_business.shortcode.in?(EMU_STAGE_1_SHORTCODES) &&
        !actor.enterprise_managed_business.shortcode.in?(EMU_STAGE_3_SHORTCODES)
      else
        false
      end
    end

    # stage-3 is high visibility/impact enterprises in EMU-Beta.
    # Kept in sync with https://data.githubapp.com/sql/share/31ef9f15
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_stage_3(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.shortcode.in?(EMU_STAGE_3_SHORTCODES)
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.shortcode.in?(EMU_STAGE_3_SHORTCODES)
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.shortcode.in?(EMU_STAGE_3_SHORTCODES)
      else
        false
      end
    end

    # A subset of staff owned enterprises or users & organizations for testing purposes.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_1(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.staff_owned? && actor.shortcode.in?(EMU_STAGE_1_SHORTCODES)
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.staff_owned? && actor.business&.shortcode.in?(EMU_STAGE_1_SHORTCODES)
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.staff_owned? &&
        actor.enterprise_managed_business.shortcode.in?(EMU_STAGE_1_SHORTCODES)
      else
        false
      end
    end

    # The rest of the staff owned enterprises or users & organizations for testing purposes.
    # All staff owned enterprises that did not fall into stage 1
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_2(actor)
      excluded_shortcodes = EMU_STAGE_1_SHORTCODES + [EMU_MICROSOFT_SHORTCODE]
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.staff_owned? && !actor.shortcode.in?(excluded_shortcodes)
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.staff_owned? && !actor.business&.shortcode.in?(excluded_shortcodes)
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.staff_owned? &&
        !actor.enterprise_managed_business.shortcode.in?(excluded_shortcodes)
      else
        false
      end
    end

    # stage-3 contains all of the non-staff owned enterprises in EMU with exception of premium support plan enterprises.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_3(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && !actor.staff_owned? && \
          !actor.has_premium_support_plan? && !actor.has_premium_plus_support_plan?
      when Organization
        actor.enterprise_managed_user_enabled? && !actor.business&.staff_owned? && \
          !actor.business&.has_premium_support_plan? && !actor.business&.has_premium_plus_support_plan?
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        !actor.enterprise_managed_business.staff_owned? &&
        !actor.enterprise_managed_business.has_premium_support_plan? &&
        !actor.enterprise_managed_business.has_premium_plus_support_plan?
      else
        false
      end
    end

    # stages-4.x all of the non-staff owned enterprises in EMU with premium support plan exception of premium plus support plan enterprises.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_41(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.has_premium_support_plan? && \
          0 <= actor.id % 100 && actor.id % 100 <= T.must(EMU_STAGE_4_SETUP[:emu_group_41])
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.has_premium_support_plan? && \
          0 <= actor.business&.id % 100 && actor.business&.id % 100 <= T.must(EMU_STAGE_4_SETUP[:emu_group_41])
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.has_premium_support_plan? &&
        0 <= actor.enterprise_managed_business.id % 100 &&
        actor.enterprise_managed_business.id % 100 <= EMU_STAGE_4_SETUP[:emu_group_41]
      else
        false
      end
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_42(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.has_premium_support_plan? && \
          T.must(EMU_STAGE_4_SETUP[:emu_group_41]) < actor.id % 100 && actor.id % 100 <= T.must(EMU_STAGE_4_SETUP[:emu_group_42])
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.has_premium_support_plan? && \
          T.must(EMU_STAGE_4_SETUP[:emu_group_41]) < actor.business&.id % 100 && actor.business&.id % 100 <= T.must(EMU_STAGE_4_SETUP[:emu_group_42])
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.has_premium_support_plan? &&
        T.must(EMU_STAGE_4_SETUP[:emu_group_41]) < actor.enterprise_managed_business.id % 100 &&
        actor.enterprise_managed_business.id % 100 <= EMU_STAGE_4_SETUP[:emu_group_42]
      else
        false
      end
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_43(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && actor.has_premium_support_plan? && \
          T.must(EMU_STAGE_4_SETUP[:emu_group_42]) < actor.id % 100 && actor.id % 100 <= T.must(EMU_STAGE_4_SETUP[:emu_group_43])
      when Organization
        actor.enterprise_managed_user_enabled? && actor.business&.has_premium_support_plan? && \
          T.must(EMU_STAGE_4_SETUP[:emu_group_42]) < actor.business&.id % 100 && actor.business&.id % 100 <= T.must(EMU_STAGE_4_SETUP[:emu_group_43])
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        actor.enterprise_managed_business.has_premium_support_plan? &&
        T.must(EMU_STAGE_4_SETUP[:emu_group_42]) < actor.enterprise_managed_business.id % 100 &&
        actor.enterprise_managed_business.id % 100 <= EMU_STAGE_4_SETUP[:emu_group_43]
      else
        false
      end
    end

    # stage-5 All of the premium plus enterprises or users & organizations for testing purposes.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.emu_group_5(actor)
      case actor
      when Business
        actor.enterprise_managed_user_enabled? && (actor.has_premium_plus_support_plan? || actor.shortcode == EMU_MICROSOFT_SHORTCODE)
      when Organization
        actor.enterprise_managed_user_enabled? && (actor.business&.has_premium_plus_support_plan? || actor.business&.shortcode == EMU_MICROSOFT_SHORTCODE)
      when User
        actor.is_enterprise_managed? &&
        actor.enterprise_managed_business.present? &&
        (
          actor.enterprise_managed_business.has_premium_plus_support_plan? ||
          actor.enterprise_managed_business.shortcode == EMU_MICROSOFT_SHORTCODE
        )
      else
        false
      end
    end

    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.copilot_enterprise_seat_holder(actor)
      begin
        actor.is_a?(User) && Copilot::User.new(actor).has_cfe_access?
      # This shouldn't be needed for Vexi but will leave it for now
      # In general, this is only one way an enable check can fail, ideally, that's where errors should be handled
      rescue => e
        Failbot.report(e, actor: actor)
        false
      end
    end

    # Copilot users belonging to organizations that have opted into Copilot in GitHub.com preview features.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor), feature_name: String).returns(T::Boolean) }
    def self.beta_features_github_chat(actor, feature_name)
      begin
        actor.is_a?(User) && Copilot::User.new(actor).beta_features_github_chat_enabled?
      rescue => e
        Failbot.report(e, actor: actor)
        false
      end
    end

    # Users that got access to hadron via Copilot Code Review at the point of removing the public preview list.
    sig { params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean) }
    def self.hadron_enrolled_users(actor)
      begin
        feature_name = "copilot_code_review_public_preview"
        # we have decided to set the cutoff date to be 3/21/2025. So we want to include _all_ the possible signups on
        # that date. So our check is going to be the day _after_ the cutoff.
        cutoff_date = DateTime.new(2025, 3, 22)
        membership = EarlyAccessMembership.find_by(actor: actor, feature_slug: feature_name)
        return false unless membership

        membership_enabled = early_access_enabled(actor, feature_name)
        membership_enabled && membership.created_at < cutoff_date
      rescue => e
        Failbot.report(e, actor: actor)
        false
      end
    end

    # actor is untyped here because importing flipper seems to cause tests to fail.
    CustomGateProcType = T.type_alias { T.proc.params(actor: T.untyped, feature_name: String).returns(T::Boolean) }

    # This wrapper allows for the creation of a proc that can be type checked by Sorbet.
    sig { params(blk: CustomGateProcType).returns(CustomGateProcType) }
    def self.make_custom_gate_proc(&blk)
      blk
    end

    # Wrap the custom gate proc in a memoization layer to avoid re-evaluating the proc for the same actor.
    # Note: This only works for custom gates that are not dependent on the feature name.
    sig { params(custom_gate_name: String, blk: T.proc.params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor)).returns(T::Boolean)).returns(CustomGateProcType) }
    def self.memoize_custom_gate_proc(custom_gate_name, &blk)
      make_custom_gate_proc do |actor, _|
        result = false
        if actor.is_a?(GitHub::VexiActor) || actor.is_a?(GitHub::IFlipperActor) || (actor.respond_to?(:thing) && actor.thing.is_a?(GitHub::IFlipperActor))
          gh_actor = actor.respond_to?(:thing) ? T.cast(actor.thing, GitHub::IFlipperActor) : actor

          result = gh_actor.memoized_custom_gates[custom_gate_name]
          if result.nil?
            result = yield gh_actor
            gh_actor.memoized_custom_gates[custom_gate_name] = result
          end
        end

        result
      end
    end

    # This wrapper creates a custom gate proc that doesn't user memoization
    sig { params(blk: T.proc.params(actor: T.any(GitHub::IFlipperActor, GitHub::VexiActor), feature_name: String).returns(T::Boolean)).returns(CustomGateProcType) }
    def self.custom_gate_proc(&blk)
      make_custom_gate_proc do |actor, feature_name|
        result = false
        if actor.is_a?(GitHub::VexiActor) || actor.is_a?(GitHub::IFlipperActor) || (actor.respond_to?(:thing) && actor.thing.is_a?(GitHub::IFlipperActor))
          gh_actor = actor.respond_to?(:thing) ? T.cast(actor.thing, GitHub::IFlipperActor) : actor
          result = yield(gh_actor, feature_name)
        end
        result
      end
    end

    if GitHub.multi_tenant_enterprise?
      CUSTOM_GATES = T.let({
        "copilot_enterprise_seat_holder" => memoize_custom_gate_proc("copilot_enterprise_seat_holder") { |actor| copilot_enterprise_seat_holder(actor) },
      }, T::Hash[String, CustomGateProcType])
    else
      CUSTOM_GATES = T.let({
        "preview_features" => memoize_custom_gate_proc("preview_features") { |actor| preview_features(actor) },
        "bounty_hunter_target" => memoize_custom_gate_proc("bounty_hunter_target") { |actor| bounty_hunter_target(actor) },
        "beta_features_github_chat" => custom_gate_proc { |actor, feature_name| beta_features_github_chat(actor, feature_name) },
        "copilot_enterprise_seat_holder" => memoize_custom_gate_proc("copilot_enterprise_seat_holder") { |actor| copilot_enterprise_seat_holder(actor) },
        "developer_relations" => memoize_custom_gate_proc("developer_relations") { |actor| developer_relations(actor) },
        "maintainers_early_access" => memoize_custom_gate_proc("maintainers_early_access") { |actor| maintainers_early_access(actor) },
        "integrators_early_access" => memoize_custom_gate_proc("integrators_early_access") { |actor| integrators_early_access(actor) },
        "early_access_enabled" => custom_gate_proc { |actor, feature_name| early_access_enabled(actor, feature_name) }, # This uses the feature_name, so we cannot memoize it.
        "azure_stacks_collaborators" => memoize_custom_gate_proc("azure_stacks_collaborators") { |actor| azure_stacks_collaborators(actor) },
        "stacks_contributors" => memoize_custom_gate_proc("stacks_contributors") { |actor| stacks_contributors(actor) },
        "microsoft_team_members" => memoize_custom_gate_proc("microsoft_team_members") { |actor| microsoft_team_members(actor) },
        "github_stars_members" => memoize_custom_gate_proc("github_stars_members") { |actor| github_stars_members(actor) },
        "shopify_members" => memoize_custom_gate_proc("shopify_members") { |actor| shopify_members(actor) },
        "microsoft_emu_members" => memoize_custom_gate_proc("microsoft_emu_members") { |actor| microsoft_emu_members(actor) },
        "microsoft_emu_copilot_members" => memoize_custom_gate_proc("microsoft_emu_copilot_members") { |actor| microsoft_emu_copilot_members(actor) },
        "microsoft_copilot_members" => memoize_custom_gate_proc("microsoft_copilot_members") { |actor| microsoft_copilot_members(actor) },
        "microsoft_mvps" => memoize_custom_gate_proc("microsoft_mvps") { |actor| microsoft_mvps(actor) },
        "ghec_invoiced_businesses" => memoize_custom_gate_proc("ghec_invoiced_businesses") { |actor| ghec_invoiced_businesses(actor) },
        "emu_stage_1" => memoize_custom_gate_proc("emu_stage_1") { |actor| emu_stage_1(actor) },
        "emu_stage_2" => memoize_custom_gate_proc("emu_stage_2") { |actor| emu_stage_2(actor) },
        "emu_stage_3" => memoize_custom_gate_proc("emu_stage_3") { |actor| emu_stage_3(actor) },
        "emu_group_1" => memoize_custom_gate_proc("emu_group_1") { |actor| emu_group_1(actor) },
        "emu_group_2" => memoize_custom_gate_proc("emu_group_2") { |actor| emu_group_2(actor) },
        "emu_group_3" => memoize_custom_gate_proc("emu_group_3") { |actor| emu_group_3(actor) },
        "emu_group_41" => memoize_custom_gate_proc("emu_group_41") { |actor| emu_group_41(actor) },
        "emu_group_42" => memoize_custom_gate_proc("emu_group_42") { |actor| emu_group_42(actor) },
        "emu_group_43" => memoize_custom_gate_proc("emu_group_43") { |actor| emu_group_43(actor) },
        "emu_group_5" => memoize_custom_gate_proc("emu_group_5") { |actor| emu_group_5(actor) },
        "hadron_enrolled_users" => memoize_custom_gate_proc("hadron_enrolled_users") { |actor| hadron_enrolled_users(actor) },
      }.freeze, T::Hash[String, CustomGateProcType])
    end
  end
end
