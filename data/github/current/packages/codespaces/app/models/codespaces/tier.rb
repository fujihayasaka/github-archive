# typed: true
# frozen_string_literal: true

module Codespaces
  class Tier
    class NoOwnersGivenError < StandardError; end

    class Config
      attr_reader :codespaces_per_user, :concurrent_cores, :concurrent_codespaces

      def initialize(args)
        @codespaces_per_user = args.fetch(:codespaces_per_user)
        @concurrent_cores = args.fetch(:concurrent_cores)
        @concurrent_codespaces = args.fetch(:concurrent_codespaces)
      end
    end

    # @param user [User] The user to calculate the tier for
    # @return [TrustTiers::TierResult] The tier for the given user
    def self.for_user(user)
      GitHub.tracer.in_span("codespaces/tier#for_user", kind: :internal) do
        # Avoid querying all the associations if we're forcing the user to be trusted anyway.
        cached_tier = Codespaces::UserTierCache.get(user_id: user.id)

        result = cached_tier.present? ? "result:hit" : "result:miss"
        GitHub.dogstats.increment("codespaces.tier.for_user.cache", tags: [result])

        if cached_tier.present?
          return cached_tier
        end

        calculated_tier = calculate_for_user(user)

        begin
          key = Codespaces::UserTierCache.key(user_id: user.id)
          mutex = GitHub::Redis::ConcurrencySafeMutex.new(key)
          mutex.lock do
            Codespaces::UserTierCache.set(user_id: user.id, tier_result: calculated_tier)
          end
        rescue GitHub::Redis::Mutex::LockError => e
          # Purposefully swallowing this -- we'll use our calculated value but not cache
          GitHub.dogstats.increment("codespaces.tier.for_user.cache.locked")
        end

        calculated_tier
      end
    end

    # @param user [User] The user to calculate the tier for
    # @return [TrustTiers::TierResult] The tier for the given user
    def self.calculate_for_user(user)
      owners = billable_associated_orgs(user)

      owners.each do |org|
        if org.respond_to?(:business) && org.business.present?
          owners << org.business
        end
      end

      owners += [billable_enterprise_managed_business(user)].compact

      user_tier = for_billable_owner(user)

      owner_tiers = owners.map do |owner|
        [owner, for_billable_owner(owner)]
      end

      owner_tiers << [user, user_tier]

      GitHub.dogstats.distribution("codespaces.tier.for_user.billable_owners.size", owner_tiers.size)

      calculated_tier = owner_tiers.sort_by do |(_, tier)|
        tier.tier
      end.first.last

      log_for_user_calculation_results(user, user_tier, calculated_tier, owner_tiers)

      calculated_tier
    end
    private_class_method :calculate_for_user

    def self.log_for_user_calculation_results(user, user_tier, calculated_tier, owner_tiers)
      GitHub.tracer.in_span("codespaces/tier.log_for_user_calculation_results", kind: :internal) do
        deciding_owner_logins = []
        nonspendable_deciding_owner_logins = []
        owner_tiers.each do |(owner, tier)|
          if tier == calculated_tier
            if owner.is_a?(Organization)
              deciding_owner_logins << "org:#{owner.login}"  # rubocop:disable GitHub/DoNotAllowLogin
              nonspendable_deciding_owner_logins << "org:#{owner.login}" unless allows_codespaces_spending?(owner)  # rubocop:disable GitHub/DoNotAllowLogin
            elsif owner.is_a?(User)
              deciding_owner_logins << "user:#{owner.login}" # rubocop:disable GitHub/DoNotAllowLogin
            elsif owner.is_a?(Business)
              deciding_owner_logins << "business:#{owner.name}"
            end
          end
        end
        GitHub.logger.info(
          "Codespaces tier calculation results",
          "gh.user.login" => user.login, # rubocop:disable GitHub/DoNotAllowLogin
          "gh.codespaces.user_tier" => user_tier.tier,
          "gh.codespaces.calculated_tier" => calculated_tier.tier,
          "gh.codespaces.tier_deciding_logins" => deciding_owner_logins.sort,
          "gh.codespaces.nonspendable_tier_deciding_logins" => nonspendable_deciding_owner_logins.sort,
          "code.namespace" => "Codespaces::Tier",
          "code.function" => "for_user",
        )

        Codespaces::Events.trust_tier_calculated(user, calculated_tier.tier, deciding_owner_logins.sort)

        if deciding_owner_logins.sort == nonspendable_deciding_owner_logins.sort
          GitHub.dogstats.increment("codespaces.tier.calculation_hinged_on_nonspendable_org", tags: ["tier:#{calculated_tier}"])
        end
      end
    end
    private_class_method :log_for_user_calculation_results

    # @param billable_owner [Organization] The billable owner to calculate the tier for
    # @param force_calculation [Boolean] Whether to force a calculation and skip UserSetting
    # @return [TrustTiers::TierResult] The tier for the given organization
    def self.for_billable_owner(billable_owner, force_calculation: false)
      GitHub.tracer.in_span("codespaces/tier.for_billable_owner", kind: :internal) do
        TrustTiers::Tier.for_billable_owner(billable_owner, force_calculation: force_calculation)
      end
    end

    CODESPACES_PER_USER = 30
    def self.get_config_map(user)
      {
        TrustTiers::Tier::TRUSTED => Config.new(codespaces_per_user: CODESPACES_PER_USER, concurrent_cores: 64, concurrent_codespaces: 5),
        TrustTiers::Tier::NEUTRAL => Config.new(codespaces_per_user: CODESPACES_PER_USER, concurrent_cores: 16, concurrent_codespaces: 2),
        TrustTiers::Tier::UNTRUSTED => Config.new(codespaces_per_user: CODESPACES_PER_USER, concurrent_cores: 16, concurrent_codespaces: 2),
      }
    end

    # This accepts a TierResult object
    def self.config_for_tier(tier, user)
      get_config_map(user).fetch(tier.tier)
    end

    # We use the enterprise_managed_business when it is present
    # which it is when the actor is an EMU and in proxima where all users are EMU which establishes a strong connection to the business
    def self.billable_enterprise_managed_business(actor)
      GitHub.tracer.in_span("codespaces/tier.billable_enterprise_managed_business", kind: :internal) do
        return nil unless actor.respond_to?(:enterprise_managed_business)

        actor.enterprise_managed_business
      end
    end

    def self.billable_associated_orgs(user)
      GitHub.tracer.in_span("codespaces/tier.billable_associated_orgs", kind: :internal) do
        associated_orgs = user.organizations.to_a
        # if `user` is an org, calling `.outside_collaborator_organizations` will
        # return itself for some reason. If you then do the `async_can_bill?`
        # check on that org, it will fail because authzd doesn't like checking if
        # something has permissions on itself, so we just short-circuit here, if
        # it's an org.
        collaborating_orgs = if user.organization?
          []
        else
          user.outside_collaborator_organizations.to_a
        end

        # hash in the form of {org => can_bill}
        org_billability = {}

        promises = associated_orgs.map do |org|
          Codespaces::OrgPolicy.new(user: user, org: org).async_can_bill?.then do |can_bill|
            org_billability[org] = can_bill
          end
        end

        promises += collaborating_orgs.map do |org|
          Codespaces::OrgPolicy.new(user: user, org: org, known_org_relationship: :collaborator).async_can_bill?.then do |can_bill|
            org_billability[org] = can_bill
          end
        end

        Promise.all(promises).sync

        billable_associated_orgs = (associated_orgs + collaborating_orgs).select do |org|
          org_billability[org]
        end

        billable_associated_orgs
      end
    end
    private_class_method :billable_associated_orgs

    def self.allows_codespaces_spending?(org)
      GitHub.tracer.in_span("codespaces/tier.allows_codespaces_spending?", kind: :internal) do
        return true if org.feature_enabled?(:codespaces_v_next_fix_budget_calls) && org.billing_v_next_enabled_for_codespaces?
        billable_owner = org.billable_owner
        active_budget = billable_owner.budget_for(group: "codespaces")
        if billable_owner.feature_enabled?(:ghe_spending_limits)
          org_budget = org.budget_for(group: "codespaces")
          active_budget = org_budget if org_budget.persisted?
        end
        return true unless active_budget.enforce_spending_limit
        active_budget.spending_limit_in_subunits > 0
      end
    end
    private_class_method :allows_codespaces_spending?
  end
end
