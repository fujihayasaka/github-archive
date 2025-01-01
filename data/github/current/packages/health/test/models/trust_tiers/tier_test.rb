# typed: true
# frozen_string_literal: true

require "test_helper"

class TrustTierTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @known_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_FREE_AGE_LIMIT.ago - 1.day)
    @new_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago + 1.day)

    @neutral_paid_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)
    @neutral_couponed_user = create(:user, created_at: TrustTiers::TierDetails::NEUTRAL_PAID_OR_COUPONED_AGE_LIMIT.ago - 1.day)

    @neutral_couponed_user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago + 1.day)
    @trusted_couponed_user = create(:user, created_at: TrustTiers::TierDetails::TRUSTED_COUPONED_AGE_LIMIT.ago - 1.day)

    @educational_coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
    @non_educational_coupon = create(:coupon, group: "internal")
  end

  if GitHub.enterprise?
    test "trusted for all users" do
      result = TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::GITHUB_ENTERPRISE)
      assert_equal result, TrustTiers::Tier.for_billable_owner(@new_user.reload)
      assert_equal ["GitHub Enterprise"], result.verbose_reason
    end
  end

  ########################################################
  # Calculate tier v1
  ########################################################
  class CalculateTierV1 < TrustTierTest
    context "calculate tier", skip_enterprise: true do

      setup do # rubocop:disable GitHub/NestedSetupTeardown - we can clean this up once v1 is removed
        disable_feature_flag(:trust_tier_1_business_test)
        disable_feature_flag(:billing_update_trust_tier_rules)
        disable_feature_flag(:trust_tier_updates_business_exclusion)
      end

      context "#for_billable_owner" do
        # **************** TRUSTED ****************
        # * Sales serve accounts (invoiced Organization or Invoiced Enterprise)
        #    *************   OR    *************
        # * Accounts with established billing history
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        #    *************   OR    *************
        # * Oldest account owner > 14 days old AND has eligible coupon
        context "TRUSTED" do
          test "returns TRUSTED if the billing plan owner is an invoiced Enterprise Account" do
            enterprise = create(:business)
            owner_details = TrustTiers::TierDetails.new(enterprise)
            client_name = "my_test_client"
            GitHub.logger.expects(:info).with(
              "code.namespace" => "TrustTiers::Tier",
              "code.function" => "for_billable_owner",
              "gh.enterprise" => GitHub.enterprise?,
              "gh.catalog_service" => "github/trust_tiers",
              "gh.owner.database_id" => enterprise.id,
              "gh.owner.global_id" => enterprise.global_relay_id,
              "gh.owner.invoiced" => enterprise.invoiced?,
              "gh.owner.business" => enterprise.is_a?(Business),
              "gh.owner.trial" => enterprise.trial?,
              "has_eligible_coupon" => owner_details.has_eligible_coupon?,
              "has_established_billing_history" => owner_details.has_established_billing_history?,
              "last_payment_failed" => owner_details.last_payment_failed?,
              "has_paid_money" => owner_details.has_paid_money?,
              "is_paid_plan" => owner_details.is_paid_plan?,
              "oldest_owner_older_than_trusted_couponed_age_limit" => owner_details.oldest_owner_older_than_trusted_couponed_age_limit?,
              "oldest_owner_older_than_neutral_free_age_limit" => owner_details.oldest_owner_older_than_neutral_free_age_limit?,
              "oldest_owner_older_than_neutral_paid_or_couponed_age_limit" => owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?,
              "oldest_owner_age" => owner_details.oldest_owner_age,
              "oldest_owner" => owner_details.oldest_owner,
              "client_name" => client_name,
              "calculated_tier" => TrustTiers::Tier::TRUSTED,
              "tier_reason" => TrustTiers::TierResult::BUSINESS_OR_INVOICED,
              "former_calculated_tier" => nil,
              "former_tier_reason" => nil,
              "v2_tier_difference" => 0
            )
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(enterprise.reload, client_name)
          end

          test "returns TRUSTED if the billing plan owner is invoiced" do
            org = create(:invoiced_organization, plan: "business_plus")
            owner_details = TrustTiers::TierDetails.new(org)
            client_name = "my_client"
            GitHub.logger.expects(:info).with(
              "code.namespace" => "TrustTiers::Tier",
              "code.function" => "for_billable_owner",
              "gh.enterprise" => GitHub.enterprise?,
              "gh.catalog_service" => "github/trust_tiers",
              "gh.owner.database_id" => org.id,
              "gh.owner.global_id" => org.global_relay_id,
              "gh.owner.invoiced" => org.invoiced?,
              "gh.owner.business" => org.is_a?(Business),
              "gh.owner.trial" => "NA",
              "has_eligible_coupon" => owner_details.has_eligible_coupon?,
              "has_established_billing_history" => owner_details.has_established_billing_history?,
              "last_payment_failed" => owner_details.last_payment_failed?,
              "has_paid_money" => owner_details.has_paid_money?,
              "is_paid_plan" => owner_details.is_paid_plan?,
              "oldest_owner_older_than_trusted_couponed_age_limit" => owner_details.oldest_owner_older_than_trusted_couponed_age_limit?,
              "oldest_owner_older_than_neutral_free_age_limit" => owner_details.oldest_owner_older_than_neutral_free_age_limit?,
              "oldest_owner_older_than_neutral_paid_or_couponed_age_limit" => owner_details.oldest_owner_older_than_neutral_paid_or_couponed_age_limit?,
              "oldest_owner_age" => owner_details.oldest_owner_age,
              "oldest_owner" => owner_details.oldest_owner,
              "client_name" => client_name,
              "calculated_tier" => TrustTiers::Tier::TRUSTED,
              "tier_reason" => TrustTiers::TierResult::BUSINESS_OR_INVOICED,
              "former_calculated_tier" => nil,
              "former_tier_reason" => nil,
              "v2_tier_difference" => 0
            )
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(org.reload, client_name)
          end

          test "returns TRUSTED if account is older than limit and has non-educational coupon" do
            org = create(:business_plus_organization, admin: @trusted_couponed_user)
            org.redeem_coupon(@non_educational_coupon)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if account has non-educational coupon but is younger than the limit" do
            org = create(:business_plus_organization, admin: @neutral_couponed_user)
            org.redeem_coupon(@non_educational_coupon)
            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns TRUSTED if organization has established billing history" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 66.days.ago)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if only billing has been zero cents" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if only billing has been refunded" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if there's no billing tx at least two months old" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "not TRUSTED if only owner was created less than limit" do
            org = create(:team_org, admins: [@known_user])
            refute_equal TrustTiers::Tier::TRUSTED, TrustTiers::Tier.for_billable_owner(org.reload).tier
          end

          test "TRUSTED if enterprise trial and Invoiced" do
            org = create(:organization, admins: [@known_user])
            business = create(:business, trial_expires_at: 3.days.from_now)
            business.add_organization(org)
            org.reload
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED), TrustTiers::Tier.for_billable_owner(org.business)
          end

          test "not TRUSTED if free org" do
            org = create(:free_org, admins: [@known_user], plan: GitHub::Plan.free)
            refute_equal TrustTiers::Tier::TRUSTED, TrustTiers::Tier.for_billable_owner(org.reload).tier
          end

          test "returns forced tier even if the billing plan owner is invoiced NEUTRAL" do
            org = create(:invoiced_organization, plan: "business_plus")
            owner_details = TrustTiers::TierDetails.new(org)
            client_name = "my_client"
            org.settings.set!(:trust_tier, TrustTiers::Tier::NEUTRAL)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::SETTINGS_FORCED),
              TrustTiers::Tier.for_billable_owner(org.reload, client_name)
          end

          test "returns forced tier even if the billing plan owner is invoiced UNTRUSTED" do
            org = create(:invoiced_organization, plan: "business_plus")
            owner_details = TrustTiers::TierDetails.new(org)
            client_name = "my_client"
            org.settings.set!(:trust_tier, TrustTiers::Tier::UNTRUSTED)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::SETTINGS_FORCED),
              TrustTiers::Tier.for_billable_owner(org.reload, client_name)
          end
        end

        context "NEUTRAL" do
          # **************** NEUTRAL ****************
          # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful)
          #    *************   OR    *************
          # * Oldest account owner > 3 days old AND has eligible coupon
          #    *************   OR    *************
          # * Oldest account owner created more than 30 days ago
          test "returns NEUTRAL if the oldest account owner is greater than the neutral tier free account age limit" do
            org = create(:organization, admins: [@known_user], plan: GitHub::Plan.business)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns NEUTRAL if account has a paid plan that actually paid money" do
            org = create(:organization, admins: [@neutral_paid_user], plan: GitHub::Plan.business)
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::PAID),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns NEUTRAL if account has a non-education coupon that is newer than limit" do
            org = create(:organization, admins: [@neutral_couponed_user], plan: GitHub::Plan.business)
            org.redeem_coupon(@non_educational_coupon)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::COUPON),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns NEUTRAL if enterprise trial and old user" do
            org = create(:organization, admins: [@known_user])
            business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
            business.add_organization(org)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE), TrustTiers::Tier.for_billable_owner(org.reload)
          end
        end

        context "UNTRUSTED" do
          # **************** UNTRUSTED ****************
          # * Everyone else
          test "returns UNTRUSTED if the oldest account owner is less than limit" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and refunded money" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and free org" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.free)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and enterprise trial" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business_plus)
            Billing::EnterpriseCloudTrial.new(org).create
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if enterprise trial" do
            org = create(:organization, admins: [@new_user])
            business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
            business.add_organization(org)
            org.reload
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::ENTERPRISE_TRIAL), TrustTiers::Tier.for_billable_owner(org.business)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and has education coupon" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
            org.redeem_coupon(@educational_coupon)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end
        end

        context "FORCING TIER" do
          test "returns TRUSTED if :trust_tier forced" do
            org = create(:free_org, admins: [@known_user], plan: GitHub::Plan.free)
            org.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::SETTINGS_FORCED),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end
        end
      end

      context "#for_repository", skip_enterprise: true do
        test "resolves tier when the repository owner is an Enterprise Account" do
          org = create(:enterprise_linked_organization)
          repo = create(:repository, owner: org)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
            TrustTiers::Tier.for_repository(repo.reload)
        end
        test "returns TRUSTED if repo is engaged OSS" do
          public_repo = create(:public_repository, name: "public-repo-1", created_at: 2.months.ago, pushed_at: 2.years.ago)
          make_searchable public_repo
          # using a query similar to the one used in the EngagedOss model but without the stars filter
          query_phrase = "is:public archived:false fork:false
                          created:<#{1.month.ago.strftime("%Y-%m-%d")}
                          pushed:>#{1.year.ago.strftime("%Y-%m-%d")}"
          repos = TrustTiers::EngagedOss.get_repos(query_phrase)
          TrustTiers::EngagedOss.populate_repos(repos)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ENGAGED_OSS),
          TrustTiers::Tier.for_repository(public_repo.reload)
        end
        test "resolves tier when the repository owner is a non-enterprise org" do
          org = create(:organization, admins: [@known_user], plan: GitHub::Plan.free)
          repo = create(:repository, owner: org)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE),
            TrustTiers::Tier.for_repository(repo.reload)
        end
        test "resolves tier when the repository owner is a user" do
          repo = create(:repository, owner: @known_user)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE),
            TrustTiers::Tier.for_repository(repo.reload)
        end
      end
    end
  end

  ########################################################
  # Calculate tier v2
  ########################################################
  class CalculateTierV2 < TrustTierTest
    context "calculate tier", skip_enterprise: true do

      setup do # rubocop:disable GitHub/NestedSetupTeardown - we can clean this up once v1 is removed
        enable_feature_flag(:trust_tier_1_business_test)
        enable_feature_flag(:billing_update_trust_tier_rules)
        enable_feature_flag(:org_upgraded_trust_tiers_v2)
        disable_feature_flag(:trust_tier_updates_business_exclusion)
      end

      context "#for_billable_owner" do
        # **************** TRUSTED ****************
        # * Sales serve accounts (invoiced Organization or Invoiced Enterprise)
        #    *************   OR    *************
        # * Accounts with established billing history
        #     * Most recent payment was successful
        #     * One successful payment at least two months ago
        #    *************   OR    *************
        # * Oldest account owner > 14 days old AND has eligible coupon
        context "TRUSTED" do
          test "returns TRUSTED if the billing plan owner is an invoiced Enterprise Account" do
            enterprise = create(:business)
            owner_details = TrustTiers::TierDetails.new(enterprise)
            client_name = "my_test_client"

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(enterprise.reload, client_name)
          end

          test "returns TRUSTED if the billing plan owner is invoiced" do
            org = create(:invoiced_organization, plan: "business_plus")
            owner_details = TrustTiers::TierDetails.new(org)
            client_name = "my_client"

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(org.reload, client_name)
          end

          test "returns TRUSTED if the account was previously invoiced" do
            enable_feature_flag(:was_invoiced_kv)
            org = create(:invoiced_organization, plan: "business_plus")
            org.update(billing_type: ::Customer::BILLING_TYPE_CARD)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(org.reload)

            business = create(:business)
            business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(business.reload)
          end

          test "returns TRUSTED if account is older than limit and has non-educational coupon" do
            org = create(:business_plus_organization, admin: @trusted_couponed_user)
            org.redeem_coupon(@non_educational_coupon)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns TRUSTED if business is not invoiced or established billing history, but has non-educational coupon" do
            @business = create(:business, :with_self_serve_payment, created_at: 60.days.ago, customer: create(:customer, billing_attempts: 1),
            owners: [@trusted_couponed_user])
            @business.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
            @coupon = create(:coupon, group: "internal")
            @business.redeem_coupon(@coupon.code, actor: @trusted_couponed_user)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON),
              TrustTiers::Tier.for_billable_owner(@business.reload)
          end

          test "does not return TRUSTED if account has non-educational coupon but is younger than the limit" do
            org = create(:business_plus_organization, admin: @neutral_couponed_user)
            org.redeem_coupon(@non_educational_coupon)
            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::TRUSTED_COUPON),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns TRUSTED if Enterprise has established billing history" do
            business = create(:business, :with_self_serve_payment, created_at: 60.days.ago)
            create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 66.days.ago)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(business)
          end

          test "does not return TRUSTED if self serve Enterprise and their last payment failed i.e. in dunning because of billing attempts being greater than 0" do
            business = create(:business, :with_self_serve_payment, created_at: 60.days.ago, customer: create(:customer, billing_attempts: 1))
            create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(business)
            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(business)
          end

          test "returns TRUSTED if organization has established billing history" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 66.days.ago)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if only billing has been zero cents" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, amount_in_cents: 0, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if only billing txs has been zero cents for enterprise" do
            business = create(:business, :with_self_serve_payment, created_at: 60.days.ago)
            create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, amount_in_cents: 0, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, customer: business.customer, asset_packs_total: 5, amount_in_cents: 0, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(business)
            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(business)
          end

          test "does not return TRUSTED if only billing has been refunded" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if only billing txs has been refunded for enterprise" do
            business = create(:business, :with_self_serve_payment, created_at: 60.days.ago)
            create(:billing_transaction, :zuora, :refunded_sale, customer: business.customer, asset_packs_total: 5, created_at: 10.days.ago)
            create(:billing_transaction, :zuora, :refunded_sale, customer: business.customer, asset_packs_total: 5, created_at: 66.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(business)
            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(business)
          end

          test "does not return TRUSTED if there's no billing tx at least two months old" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5, created_at: 10.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "does not return TRUSTED if there's no billing tx at least two months old for enterprise" do
            business = create(:business, :with_self_serve_payment, created_at: 60.days.ago)
            create(:billing_transaction, :zuora, :refunded_sale, customer: business.customer, asset_packs_total: 5, created_at: 10.days.ago)

            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(business)
            refute_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
              TrustTiers::Tier.for_billable_owner(business)
          end

          test "not TRUSTED if only owner was created less than limit" do
            org = create(:team_org, admins: [@known_user])
            refute_equal TrustTiers::Tier::TRUSTED, TrustTiers::Tier.for_billable_owner(org.reload).tier
          end

          test "not TRUSTED if enterprise not invoiced" do
            business = create(:business, :with_self_serve_payment)
            refute_equal TrustTiers::Tier::TRUSTED, TrustTiers::Tier.for_billable_owner(business.reload).tier
          end

          test "TRUSTED if enterprise trial and Invoiced" do
            org = create(:organization, admins: [@known_user])
            business = create(:business, trial_expires_at: 3.days.from_now)
            business.add_organization(org)
            org.reload
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED), TrustTiers::Tier.for_billable_owner(org.business)
          end

          test "not TRUSTED if free org" do
            org = create(:free_org, admins: [@known_user], plan: GitHub::Plan.free)
            refute_equal TrustTiers::Tier::TRUSTED, TrustTiers::Tier.for_billable_owner(org.reload).tier
          end

          test "returns forced tier even if the billing plan owner is invoiced NEUTRAL" do
            org = create(:invoiced_organization, plan: "business_plus")
            owner_details = TrustTiers::TierDetails.new(org)
            client_name = "my_client"
            org.settings.set!(:trust_tier, TrustTiers::Tier::NEUTRAL)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::SETTINGS_FORCED),
              TrustTiers::Tier.for_billable_owner(org.reload, client_name)
          end

          test "returns forced tier even if the billing plan owner is invoiced UNTRUSTED" do
            org = create(:invoiced_organization, plan: "business_plus")
            owner_details = TrustTiers::TierDetails.new(org)
            client_name = "my_client"
            org.settings.set!(:trust_tier, TrustTiers::Tier::UNTRUSTED)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::SETTINGS_FORCED),
              TrustTiers::Tier.for_billable_owner(org.reload, client_name)
          end

          test "returns TRUSTED if enterprise upgraded from an organization with established billing history" do
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
            business = create(:business, :with_self_serve_payment, upgraded_from: org)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ESTABLISHED_BILLING),
              TrustTiers::Tier.for_billable_owner(business)
          end
        end

        context "NEUTRAL" do
          # **************** NEUTRAL ****************
          # * Oldest account owner > 3 days old AND has a paid plan (has paid money and last payment was successful)
          #    *************   OR    *************
          # * Oldest account owner > 3 days old AND has eligible coupon
          #    *************   OR    *************
          # * Oldest account owner created more than 30 days ago
          test "returns NEUTRAL if the oldest account owner is greater than the neutral tier free account age limit" do
            org = create(:organization, admins: [@known_user], plan: GitHub::Plan.business)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns NEUTRAL if account has a paid plan that actually paid money" do
            org = create(:organization, admins: [@neutral_paid_user], plan: GitHub::Plan.business)
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::PAID),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns NEUTRAL if an enterprise has a paid plan that actually paid money and oldest account member is older than 3 days old" do
            business = create(:business, :with_self_serve_payment, owners: [@neutral_paid_user])
            create(:billing_transaction, :zuora, :business_owned, asset_packs_total: 5, customer: business.customer)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::PAID),
              TrustTiers::Tier.for_billable_owner(business.reload)
          end

          test "returns NEUTRAL if account has a non-education coupon that is newer than limit" do
            org = create(:organization, admins: [@neutral_couponed_user], plan: GitHub::Plan.business)
            org.redeem_coupon(@non_educational_coupon)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::COUPON),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns NEUTRAL if enterprise trial and old user" do
            org = create(:organization, admins: [@known_user])
            business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
            business.add_organization(org)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE), TrustTiers::Tier.for_billable_owner(org.reload)
          end
        end

        context "UNTRUSTED" do
          # **************** UNTRUSTED ****************
          # * Everyone else
          test "returns UNTRUSTED if the oldest account owner is less than limit" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and refunded money" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
            create(:billing_transaction, :zuora, :refunded_sale, user: org, asset_packs_total: 5)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and free org" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.free)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and enterprise trial" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business_plus)
            Billing::EnterpriseCloudTrial.new(org).create
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if enterprise trial" do
            org = create(:organization, admins: [@new_user])
            business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
            business.add_organization(org)
            org.reload
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::ENTERPRISE_TRIAL), TrustTiers::Tier.for_billable_owner(org.business)
          end

          test "returns UNTRUSTED if the oldest account owner is less than limit and has education coupon" do
            org = create(:organization, admins: [@new_user], plan: GitHub::Plan.business)
            org.redeem_coupon(@educational_coupon)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH), TrustTiers::Tier.for_billable_owner(org.reload)
          end

          test "returns UNTRUSTED if enterprise upgraded from an organization with established billing history when ff disabled" do
            disable_feature_flag(:org_upgraded_trust_tiers_v2)
            org = create(:team_org, admins: [@known_user])
            create(:billing_transaction, :zuora, user: org, asset_packs_total: 5, created_at: 3.months.ago)
            business = create(:business, :with_self_serve_payment, upgraded_from: org)

            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::UNTRUSTED, TrustTiers::TierResult::NO_MATCH),
              TrustTiers::Tier.for_billable_owner(business)
          end
        end

        context "FORCING TIER" do
          test "returns TRUSTED if :trust_tier forced" do
            org = create(:free_org, admins: [@known_user], plan: GitHub::Plan.free)
            org.settings.set!(:trust_tier, TrustTiers::Tier::TRUSTED)
            assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::SETTINGS_FORCED),
              TrustTiers::Tier.for_billable_owner(org.reload)
          end
        end
      end

      context "#for_repository", skip_enterprise: true do
        test "resolves tier when the repository owner is an Enterprise Account" do
          org = create(:enterprise_linked_organization)
          repo = create(:repository, owner: org)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::BUSINESS_OR_INVOICED),
            TrustTiers::Tier.for_repository(repo.reload)
        end
        test "returns TRUSTED if repo is engaged OSS" do
          public_repo = create(:public_repository, name: "public-repo-1", created_at: 2.months.ago, pushed_at: 2.years.ago)
          make_searchable public_repo
          # using a query similar to the one used in the EngagedOss model but without the stars filter
          query_phrase = "is:public archived:false fork:false
                          created:<#{1.month.ago.strftime("%Y-%m-%d")}
                          pushed:>#{1.year.ago.strftime("%Y-%m-%d")}"
          repos = TrustTiers::EngagedOss.get_repos(query_phrase)
          TrustTiers::EngagedOss.populate_repos(repos)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::TRUSTED, TrustTiers::TierResult::ENGAGED_OSS),
          TrustTiers::Tier.for_repository(public_repo.reload)
        end
        test "resolves tier when the repository owner is a non-enterprise org" do
          org = create(:organization, admins: [@known_user], plan: GitHub::Plan.free)
          repo = create(:repository, owner: org)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE),
            TrustTiers::Tier.for_repository(repo.reload)
        end
        test "resolves tier when the repository owner is a user" do
          repo = create(:repository, owner: @known_user)
          assert_equal TrustTiers::TierResult.new(TrustTiers::Tier::NEUTRAL, TrustTiers::TierResult::OLDEST_OWNER_AGE),
            TrustTiers::Tier.for_repository(repo.reload)
        end
      end
    end
  end
end
