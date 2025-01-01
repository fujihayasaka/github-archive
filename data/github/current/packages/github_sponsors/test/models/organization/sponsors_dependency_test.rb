# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::SponsorsDependencyTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons, admin: @org_admin)
    @org.update_default_repository_permission(:none, actor: @org_admin)
    @org_member = create(:user)
    @org_billing_manager = create(:user)

    @org_pub_repo = travel_to(1.hour.ago) { create(:repository, owner: @org, organization: @org) }
    @org_priv_repo = create(:private_repository, owner: @org, organization: @org)

    @rando = create(:user)

    @org2 = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
      plan: GitHub::Plan.free_with_addons)

    @invoiced_org = create(:invoiced_organization, :sponsors_invoiced)
    @invoiced_org_admin = @invoiced_org.admins.first
  end

  setup do
    @org.add_member(@org_member)
    @org.billing.add_manager(@org_billing_manager, actor: @org_admin)
  end

  context ".zuora_based_premium_sponsor_ids" do
    test "omits old-style non-Zuora-based org" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      org_id = transfer.sponsor_id
      assert_empty Organization.zuora_based_premium_sponsor_ids(org_ids: [org_id])
    end

    test "includes new-style Zuora-based org" do
      org_id = @invoiced_org.id
      assert_equal [org_id].to_set, Organization.zuora_based_premium_sponsor_ids(org_ids: [org_id])
    end

    test "works without specifying a subset of orgs to check" do
      result = Organization.zuora_based_premium_sponsor_ids
      assert_includes result, @invoiced_org.id
    end
  end

  context ".premium_sponsor_ids" do
    test "includes old-style non-Zuora-based org" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      org_id = transfer.sponsor_id
      assert_equal [org_id].to_set, Organization.premium_sponsor_ids(org_ids: [org_id])
    end

    test "includes new-style Zuora-based org" do
      org_id = @invoiced_org.id
      assert_equal [org_id].to_set, Organization.premium_sponsor_ids(org_ids: [org_id])
    end

    test "works without specifying a subset of orgs to check" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)

      result = Organization.premium_sponsor_ids

      assert_includes result, @invoiced_org.id
      assert_includes result, transfer.sponsor_id
    end

    test "does not include invoiced org without Sponsors-specific setup" do
      invoiced_org = create(:invoiced_org)
      assert_nil invoiced_org.sponsors_customer
      assert_empty Organization.premium_sponsor_ids(org_ids: [invoiced_org.id])
    end

    test "does not include old-style non-Zuora-based org when transfer was never completed" do
      transfer = create(:invoiced_sponsorship_transfer)
      org_id = transfer.sponsor_id
      assert_empty Organization.premium_sponsor_ids(org_ids: [org_id])
    end
  end

  context ".active_premium_sponsor_ids" do
    test "includes old-style non-Zuora-based org" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      org_id = transfer.sponsor_id
      assert_equal [org_id].to_set, Organization.active_premium_sponsor_ids(org_ids: [org_id])
    end

    test "omits new-style Zuora-based org when it doesn't have an active sponsorship" do
      assert_empty Organization.active_premium_sponsor_ids(org_ids: [@invoiced_org.id])
    end

    test "includes new-style Zuora-based org when it has an active sponsorship" do
      create(:billing_plan_subscription, :sponsors_invoiced, :zuora, customer: @invoiced_org.sponsors_customer,
        user: @invoiced_org)
      create(:sponsorship, sponsor: @invoiced_org)
      org_id = @invoiced_org.id
      assert_equal [org_id].to_set, Organization.active_premium_sponsor_ids(org_ids: [org_id])
    end

    test "works without specifying a subset of orgs to check" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      create(:billing_plan_subscription, :sponsors_invoiced, :zuora, customer: @invoiced_org.sponsors_customer,
        user: @invoiced_org)
      create(:sponsorship, sponsor: @invoiced_org)

      result = Organization.active_premium_sponsor_ids

      assert_includes result, @invoiced_org.id
      assert_includes result, transfer.sponsor_id
    end

    test "does not include invoiced org without Sponsors-specific setup" do
      invoiced_org = create(:invoiced_org)
      assert_nil invoiced_org.sponsors_customer
      assert_empty Organization.active_premium_sponsor_ids(org_ids: [invoiced_org.id])
    end

    test "does not include old-style non-Zuora-based org when transfer was never completed" do
      transfer = create(:invoiced_sponsorship_transfer)
      org_id = transfer.sponsor_id
      assert_empty Organization.active_premium_sponsor_ids(org_ids: [org_id])
    end
  end

  context "premium_sponsors scope" do
    test "includes old-style non-Zuora-based org" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      old_style_org = transfer.sponsor
      assert_includes Organization.premium_sponsors, old_style_org
    end

    test "does not include old-style non-Zuora-based org when transfer was never completed" do
      transfer = create(:invoiced_sponsorship_transfer)
      old_style_org = transfer.sponsor
      refute_includes Organization.premium_sponsors, old_style_org
    end

    test "does not include old-style non-Zuora-based org whose completed transfer was fully reversed" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      create(:invoiced_sponsorship_transfer_reversal, invoiced_sponsorship_transfer: transfer,
        amount_in_cents: transfer.amount_in_cents)
      old_style_org = transfer.sponsor
      refute_includes Organization.premium_sponsors, old_style_org
    end

    test "includes old-style non-Zuora-based org whose completed transfer was partially reversed" do
      transfer = create(:invoiced_sponsorship_transfer, :completed, amount_in_cents: 2_00)
      create(:invoiced_sponsorship_transfer_reversal, invoiced_sponsorship_transfer: transfer,
        amount_in_cents: 1_00)
      old_style_org = transfer.sponsor
      assert_includes Organization.premium_sponsors, old_style_org
    end

    test "includes new-style Zuora-based org" do
      assert_includes Organization.premium_sponsors, @invoiced_org
    end

    test "does not include invoiced org without Sponsors-specific setup" do
      invoiced_org = create(:invoiced_org)
      assert_nil invoiced_org.sponsors_customer
      refute_includes Organization.premium_sponsors, invoiced_org
    end

    test "includes only those with an active sponsorship when active_only=true" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      old_style_org = transfer.sponsor
      sponsorship = transfer.sponsorship

      result = Organization.premium_sponsors(active_only: true)
      assert_includes result, old_style_org
      refute_includes result, @invoiced_org

      create(:billing_plan_subscription, :sponsors_invoiced, :zuora, customer: @invoiced_org.sponsors_customer,
        user: @invoiced_org)
      create(:sponsorship, sponsor: @invoiced_org)

      result = Organization.premium_sponsors(active_only: true)
      assert_includes result, old_style_org
      assert_includes result, @invoiced_org

      sponsorship.update_columns(active: false, expires_at: Time.now)

      result = Organization.premium_sponsors(active_only: true)
      refute_includes result, old_style_org
      assert_includes result, @invoiced_org
    end
  end

  context "zuora_based_premium_sponsors scope" do
    test "does not include old-style non-Zuora-based org" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      old_style_org = transfer.sponsor
      refute_includes Organization.zuora_based_premium_sponsors, old_style_org
    end

    test "includes new-style Zuora-based org" do
      assert_includes Organization.zuora_based_premium_sponsors, @invoiced_org
    end

    test "does not include invoiced org without Sponsors-specific setup" do
      invoiced_org = create(:invoiced_org)
      assert_nil invoiced_org.sponsors_customer
      refute_includes Organization.zuora_based_premium_sponsors, invoiced_org
    end
  end

  context "#premium_sponsor?" do
    test "returns true for zuora-based premium sponsors org" do
      assert_predicate @invoiced_org, :premium_sponsor?
    end

    test "returns true for old-style non-zuora-based premium sponsors org" do
      transfer = create(:invoiced_sponsorship_transfer, :completed)
      old_style_org = transfer.sponsor
      assert_predicate old_style_org, :premium_sponsor?
    end

    test "returns false for org without Sponsors-specific setup" do
      non_sponsors_invoiced_org = create(:invoiced_org)
      assert_nil non_sponsors_invoiced_org.sponsors_customer
      refute_predicate non_sponsors_invoiced_org, :premium_sponsor?
    end
  end

  context "#sponsors_insights_accessible_by?" do
    test "returns false for anonymous viewer", skip_enterprise: true do
      refute @invoiced_org.sponsors_insights_accessible_by?(nil)
    end

    test "returns true for org billing manager", skip_enterprise: true do
      billing_manager = create(:user)
      @invoiced_org.billing.add_manager(billing_manager, actor: @invoiced_org_admin)
      assert @invoiced_org.sponsors_insights_accessible_by?(billing_manager)
    end

    test "returns true for org admin", skip_enterprise: true do
      assert @invoiced_org.sponsors_insights_accessible_by?(@invoiced_org_admin)
    end

    test "returns true for GitHub staff", skip_enterprise: true do
      staff = create(:user, :staff)
      assert @invoiced_org.sponsors_insights_accessible_by?(staff)
    end

    test "returns false when billing is disabled" do
      refute @invoiced_org.sponsors_insights_accessible_by?(@invoiced_org_admin)
    end unless GitHub.billing_enabled?

    test "returns false when Sponsors is disabled" do
      refute @invoiced_org.sponsors_insights_accessible_by?(@invoiced_org_admin)
    end unless GitHub.sponsors_enabled?
  end

  context "#total_direct_dependencies_sponsored" do
    if GitHub.sponsors_enabled?
      test "returns 0 when org has no sponsorships" do
        assert_empty @org.sponsorships_as_sponsor, "need an org who has never been a sponsor"
        assert_equal 0, @org.total_direct_dependencies_sponsored(viewer: @org_member)
      end

      test "returns 0 when org has only inactive sponsorships" do
        inactive_sponsorship = create(:sponsorship, :inactive, sponsor: @org)
        assert_equal 0, @org.total_direct_dependencies_sponsored(viewer: @org_member)
      end

      test "returns 0 when org has no direct dependencies" do
        create(:sponsorship, sponsor: @org)

        fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
          data: { repositoryOwnerDependencies: { dependencies: [] } },
        })
        DependencyGraph::Query.stubs(:default_backend).returns(fake_client)

        assert_equal 0, @org.total_direct_dependencies_sponsored(viewer: @org_member)
      end

      test "returns count of sponsorables from the org's direct dependencies are actively sponsored by the org" do
        sponsorship1, sponsorship2 = create_pair(:sponsorship, sponsor: @org)

        sponsorable1 = sponsorship1.sponsorable
        sponsorable2 = sponsorship2.sponsorable

        dependency1 = create(:repository_sponsorable, :owner, sponsorable: sponsorable1).repository
        dependency2 = create(:repository_sponsorable, :owner, sponsorable: sponsorable1).repository
        dependency3 = create(:repository_sponsorable, :owner, sponsorable: sponsorable2).repository

        fake_response = stub(ok?: true, value!: { dependencies: [dependency1.id, dependency2.id, dependency3.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: @org.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [@org_pub_repo.id], # expect only public repos to be checked since viewer lacks access
        )).returns(Promise.resolve(fake_response))

        assert_equal 3, @org.total_direct_dependencies_sponsored(viewer: @org_member)
      end

      test "counts projects sponsored by linked org that the org depends on" do
        org_that_gets_credit = create(:organization)
        org_that_gets_credit_repo = create(:private_repository, owner: org_that_gets_credit, organization: org_that_gets_credit)
        viewer = org_that_gets_credit.admins.first
        org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
        create(:organization_profile, organization: org_that_gets_credit,
          sponsoring_linked_organization: org_that_pays)
        sponsorship = create(:sponsorship, sponsor: org_that_pays)
        sponsorable = sponsorship.sponsorable
        dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository

        fake_response = stub(ok?: true, value!: { dependencies: [dependency.id] })
        Platform::Loaders::Dependencies.expects(:load_repository_owner_dependencies).once.with(equals(
          owner_id: org_that_gets_credit.id,
          sort_by: nil,
          package_managers: [],
          public_only: false,
          direct_only: true,
          repository_ids: [org_that_gets_credit_repo.id],
        )).returns(Promise.resolve(fake_response))

        assert_equal 1, org_that_gets_credit.total_direct_dependencies_sponsored(viewer: viewer)
      end
    else
      test "returns 0 when Sponsors is disabled" do
        create(:sponsorship, sponsor: @org)
        assert_equal 0, @org.total_direct_dependencies_sponsored(viewer: @org_member)
      end
    end
  end

  test "organizations are not eligible for their sponsorships to be matched" do
    User.any_instance.stubs(:eligible_for_sponsorship_match?).returns(true)
    sponsorable = create(:user, :sponsorable)

    refute build(:organization).eligible_for_sponsorship_match?(sponsorable: sponsorable)
  end

  # See also tests for users in packages/github_sponsors/test/models/user/sponsors_dependency_test.rb
  context "#active_sponsorships_as_sponsor_relation" do
    test "returns sponsorships that are active" do
      sponsorship = create(:sponsorship, sponsor: @org)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsor: @org)
      result = @org.active_sponsorships_as_sponsor_relation

      assert_equal [sponsorship], result
    end

    test "includes sponsorship from linked org" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      sponsorship = create(:sponsorship, sponsor: org_that_pays)

      result = org_that_gets_credit.active_sponsorships_as_sponsor_relation

      assert_equal [sponsorship], result
    end

    test "can be combined with .sponsor_visible_to scope for unlinked org" do
      private_sponsorship = create(:sponsorship, :private, sponsor: @org)

      refute_includes @org.active_sponsorships_as_sponsor_relation.sponsor_visible_to(@rando).pluck(:id),
        private_sponsorship.id, "should not include private sponsorship for non-org member"
      assert_includes @org.active_sponsorships_as_sponsor_relation.sponsor_visible_to(@org_admin).pluck(:id),
        private_sponsorship.id, "should include private sponsorship for org admin"
      assert_includes @org.active_sponsorships_as_sponsor_relation.sponsor_visible_to(@org_billing_manager)
        .pluck(:id), private_sponsorship.id, "should include private sponsorship for org billing manager"
      assert_includes @org.active_sponsorships_as_sponsor_relation.sponsor_visible_to(@org_member).pluck(:id),
        private_sponsorship.id, "should include private sponsorship for org member"
    end

    test "can be combined with .sponsor_visible_to scope for linked org" do
      org_that_gets_credit_admin = create(:user)
      org_that_gets_credit = create(:organization, admin: org_that_gets_credit_admin)

      org_that_gets_credit_billing_mgr = create(:user)
      org_that_gets_credit.billing.add_manager(org_that_gets_credit_billing_mgr, actor: org_that_gets_credit_admin)

      org_that_gets_credit_member = create(:user)
      org_that_gets_credit.add_member(org_that_gets_credit_member)

      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)

      private_sponsorship = create(:sponsorship, :private, sponsor: org_that_pays)

      refute_includes org_that_gets_credit.active_sponsorships_as_sponsor_relation.sponsor_visible_to(@rando)
        .pluck(:id), private_sponsorship.id, "should not include private sponsorship for non-org member"
      assert_includes org_that_gets_credit.active_sponsorships_as_sponsor_relation
        .sponsor_visible_to(org_that_gets_credit_admin).pluck(:id), private_sponsorship.id,
        "should include private sponsorship for org admin"
      assert_includes org_that_gets_credit.active_sponsorships_as_sponsor_relation
        .sponsor_visible_to(org_that_gets_credit_billing_mgr).pluck(:id), private_sponsorship.id,
        "should include private sponsorship for org billing manager"
      assert_includes org_that_gets_credit.active_sponsorships_as_sponsor_relation
        .sponsor_visible_to(org_that_gets_credit_member).pluck(:id), private_sponsorship.id,
        "should include private sponsorship for org member"
    end

    test "omits sponsorship for linked org when maintainer has a spammy listing" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      sponsorship = create(:sponsorship, sponsor: org_that_pays)
      assert sponsorship.sponsors_listing.mark_spammy!

      result = org_that_gets_credit.active_sponsorships_as_sponsor_relation

      assert_empty result
    end if GitHub.spamminess_check_enabled?

    test "returns only sponsorships whose Sponsors listings are still approved" do
      sponsorship_1 = create(:sponsorship, sponsor: @org)
      sponsors_listing_1 = sponsorship_1.sponsors_listing
      assert_predicate sponsors_listing_1, :approved?

      sponsorship_2 = create(:sponsorship, sponsor: @org)
      sponsorable_2 = sponsorship_2.sponsorable
      enable_feature_flag(:live_sdn_screening, sponsorable_2) # flag is needed for sdn_disable! call
      sponsors_listing_2 = sponsorable_2.sponsors_listing
      assert sponsors_listing_2.sdn_disable!

      if GitHub.spamminess_check_enabled?
        sponsorship_3 = create(:sponsorship, sponsor: @org)
        sponsors_listing_3 = sponsorship_3.sponsors_listing
        assert sponsors_listing_3.mark_spammy!
      end

      result = @org.active_sponsorships_as_sponsor_relation

      assert_includes result, sponsorship_1
      refute_includes result, sponsorship_2, "should not include sponsorship where listing is sdn_disabled"

      if GitHub.spamminess_check_enabled?
        refute_includes result, sponsorship_3, "should not include sponsorship where listing is spammy"
      end
    end
  end

  # See also tests for users in packages/github_sponsors/test/models/user/sponsors_dependency_test.rb
  context "#active_sponsorships_as_sponsor" do
    test "can be efficiently loaded for many org sponsors at once" do
      org_that_gets_credit = create(:organization)
      org_that_pays = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription))
      create(:organization_profile, organization: org_that_gets_credit, sponsoring_linked_organization: org_that_pays)
      linked_org_sponsorship = create(:sponsorship, sponsor: org_that_pays)

      create(:billing_plan_subscription, :sponsors_invoiced, :zuora, customer: @invoiced_org.sponsors_customer,
        user: @invoiced_org)
      invoiced_org_sponsorship = create(:sponsorship, sponsor: @invoiced_org)

      sponsors = [org_that_gets_credit, @invoiced_org, org_that_pays]

      expected_queries_by_table = { sponsorships: 1, organization_profiles: 1 }

      assert_query_count(expected_queries_by_table.values.sum) do
        assert_query_count_per_table(expected_queries_by_table) do
          GitHub::PrefillAssociations.prefill_batch_method(sponsors, :active_sponsorships_as_sponsor)
        end
      end

      assert_query_count(0) do
        assert_equal [linked_org_sponsorship], org_that_gets_credit.active_sponsorships_as_sponsor
        assert_equal [linked_org_sponsorship], org_that_pays.active_sponsorships_as_sponsor
        assert_equal [invoiced_org_sponsorship], @invoiced_org.active_sponsorships_as_sponsor
      end
    end
  end

  context "#active_sponsors_invoice_migration?" do
    test "true if migration key is set" do
      @org.set_active_sponsors_invoice_migration_lock
      assert_predicate @org, :active_sponsors_invoice_migration?
    end

    test "false if migration key is not set" do
      refute_predicate @org, :active_sponsors_invoice_migration?
    end
  end

  context "#active_invoiced_sponsors_agreement?" do
    test "true for sponsors invoiced credit card org" do
      org = create(:credit_card_org, :sponsors_invoiced)
      assert_predicate org, :active_invoiced_sponsors_agreement?
    end

    test "true for sponsors invoiced org" do
      org = create(:invoiced_org, :sponsors_invoiced)
      assert_predicate org, :active_invoiced_sponsors_agreement?
    end

    test "false for org that is not sponsors invoiced" do
      org = create(:credit_card_org)
      refute_predicate org, :active_invoiced_sponsors_agreement?
    end
  end if GitHub.sponsors_enabled?

  context "#sponsors_prorated_by_default?" do
    test "returns true for org that is not using invoiced sponsors billing" do
      refute_predicate @org, :sponsors_invoiced?
      assert_predicate @org, :sponsors_prorated_by_default?
    end

    if GitHub.sponsors_enabled?
      test "returns false for org that is using invoiced sponsors billing" do
        assert_predicate @invoiced_org, :sponsors_invoiced?
        refute_predicate @invoiced_org, :sponsors_prorated_by_default?
      end
    else
      test "returns true if sponsors is not enabled" do
        assert_predicate @invoiced_org, :sponsors_prorated_by_default?
      end
    end
  end

  context "#sponsors_invoicing_required_to_sponsor?" do
    test "true for invoiced org without invoiced sponsors" do
      org = create(:organization, :invoiced)

      assert_predicate org, :invoiced?
      refute_predicate org, :sponsors_invoiced?
      assert_predicate org, :sponsors_invoicing_required_to_sponsor?
    end

    test "false for invoiced org that has signed up for invoiced sponsors" do
      assert_predicate @invoiced_org, :invoiced?
      assert_predicate @invoiced_org, :sponsors_invoiced?
      refute_predicate @invoiced_org, :sponsors_invoicing_required_to_sponsor?
    end

    test "false for non-invoiced org" do
      refute_predicate @org, :invoiced?
      refute_predicate @org, :sponsors_invoiced?
      refute_predicate @org, :sponsors_invoicing_required_to_sponsor?
    end
  end if GitHub.sponsors_enabled?
end
