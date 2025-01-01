# typed: true
# frozen_string_literal: true

require "test_helper"

class MarketplaceListingTest < GitHub::TestCase
  include HydroTestHelpers
  include PlatformTestHelpers::InterfaceHelpers
  include TradeControls::SdnScreeningTestHelper

  fixtures do
    @user = create(:user)
    @admin = create(:biztools_user)

    @free_trial_category = create(:marketplace_category, name: "Free trials", acts_as_filter: true)
    @free_category = create(:marketplace_category, name: "Free", acts_as_filter: true)
    @paid_category = create(:marketplace_category, name: "Paid", acts_as_filter: true)
    @integrator_agreement = create(:marketplace_agreement)

    GitHub.flipper[:marketplace_updated_verified_creator].disable
  end

  setup do
    GitHub.stubs(:presto).returns(stub(run: [[], [[84, 42]]]))
  end

  context "#description" do
    test "includes short and full descriptions" do
      listing = build(:marketplace_listing, short_description: "Hello world",
                      full_description: "This is dog",
                      extended_description: "What's up?")

      expected = "#{listing.short_description}\n\n#{listing.full_description}"

      assert_equal expected, listing.description
    end

    test "extended_description windows line endings are removed on write" do
      listing = build(:marketplace_listing, :draft)
      listing.extended_description = "Testing \r\n new lines"

      assert_equal listing.extended_description, "Testing \n new lines"
    end

    test "full_description windows line endings are removed on write" do
      listing = build(:marketplace_listing, :draft)
      listing.full_description = "Testing \r\n new lines"

      assert_equal listing.full_description, "Testing \n new lines"
    end

    test "windows line endings are removed when using assign_attributes" do
      listing = create(:marketplace_listing, :draft)
      listing.assign_attributes({ full_description: "Testing \r\n new lines" })

      assert_equal listing.full_description, "Testing \n new lines"
    end
  end

  context "#full_description_html" do
    test "returns the html safe version of the full description" do
      listing = create(:marketplace_listing, full_description: "## Hello")

      assert_equal "<h2>Hello</h2>", listing.full_description_html
    end

    test "returns escaped html when there is unsafe script tags" do
      listing = create(:marketplace_listing, full_description: "<script>alert();</script>")

      assert_equal "&lt;script&gt;alert();&lt;/script&gt;", listing.full_description_html
    end
  end

  context "#installed_for?" do
    test "true when user has installed listing's OAuth app" do
      app = create :oauth_application
      listing = create(:marketplace_listing, :verified, listable: app)
      user = create(:user)
      create(:oauth_authorization, user: user, application: app)

      assert listing.installed_for?(user)
    end

    test "true when user has installed listing's integration" do
      app  = create(:integration)
      user = create(:user)

      listing = create(:marketplace_listing, :verified, listable: app)
      make_integration_installation(integration: app, target: user)

      assert listing.installed_for?(user)
    end

    test "false when user is nil for OAuth app listing" do
      app = create :oauth_application
      listing = create(:marketplace_listing, :verified, listable: app)

      refute listing.installed_for?(nil)
    end

    test "false when user is nil for integration listing" do
      app = create(:integration)
      listing = create(:marketplace_listing, :verified, listable: app)

      refute listing.installed_for?(nil)
    end

    test "false when user has not installed listing's OAuth app" do
      app = create :oauth_application
      listing = create(:marketplace_listing, :verified, listable: app)
      user = create(:user)

      refute listing.installed_for?(user)
    end

    test "false when user has not installed listing's integration" do
      app = create(:integration)
      listing = create(:marketplace_listing, :verified, listable: app)
      user = create(:user)

      refute listing.installed_for?(user)
    end
  end

  context "#update_trade_compliance_metadata" do
    [:user, :org].each do |account_type|
      test "doesn't set the metadata for a #{account_type} without a trade screening record" do
        owner = create_account_with_trade_screening_record(account_type)
        owner.trade_screening_record.destroy!
        create :integration, :with_marketplace_listing, owner: owner

        refute_predicate owner, :has_saved_trade_screening_record?
      end

      test "sets the metadata for #{account_type} with an integration" do
        owner = create_account_with_trade_screening_record(account_type)
        owner.reload
        create :integration, :with_marketplace_listing, owner: owner

        assert owner.reload.trade_screening_record.metadata["marketplace_app_owner"]
      end

      test "sets the metadata for #{account_type} with an oauth application" do
        owner = create_account_with_trade_screening_record(account_type)
        owner.reload

        oauth_app = create :oauth_application, user: owner
        create :marketplace_listing, listable: oauth_app

        assert owner.reload.trade_screening_record.metadata["marketplace_app_owner"]
      end

      test "clears the metadata for #{account_type} with no marketplace app" do
        owner = create_account_with_trade_screening_record(account_type)
        owner.reload

        integration = create :integration, :with_marketplace_listing, owner: owner
        oauth_app = create :oauth_application, user: owner
        create :marketplace_listing, listable: oauth_app

        assert owner.trade_screening_record.metadata["marketplace_app_owner"]
        integration.destroy!
        oauth_app.destroy!

        refute owner.trade_screening_record.metadata["marketplace_app_owner"]
      end
    end
  end

  context "#opt_out_listable_proxima_sync" do
    test "updates integration's proxima_availability to unavailable when listing is delisted" do
      integration = create :integration, :with_marketplace_listing, proxima_availability: :available
      assert_equal "available", integration.proxima_availability
      assert_predicate integration.marketplace_listing, :present?

      integration.marketplace_listing.delist!
      integration.reload

      assert_equal "unavailable", integration.proxima_availability
    end

    test "updates oauth application's proxima_availability to unavailable when listing is delisted" do
      oauth_app = create :oauth_application, proxima_availability: :available
      create :marketplace_listing, :verified, listable: oauth_app

      assert_equal "available", oauth_app.proxima_availability
      assert_predicate oauth_app.marketplace_listing, :present?

      oauth_app.marketplace_listing.delist!
      oauth_app.reload

      assert_equal "unavailable", oauth_app.proxima_availability
    end

    test "updates integration's proxima_availability to unavailable when listing is destroyed" do
      integration = create :integration, :with_marketplace_listing, proxima_availability: :available
      assert_equal "available", integration.proxima_availability
      assert_predicate integration.marketplace_listing, :present?

      integration.marketplace_listing.destroy!
      integration.reload

      assert_equal "unavailable", integration.proxima_availability
      refute_predicate integration.marketplace_listing, :present?
    end

    test "updates oauth application's proxima_availability to unavailable when listing is destroyed" do
      oauth_app = create :oauth_application, proxima_availability: :available
      create :marketplace_listing, listable: oauth_app

      assert_equal "available", oauth_app.proxima_availability
      assert_predicate oauth_app.marketplace_listing, :present?

      oauth_app.marketplace_listing.destroy!
      oauth_app.reload

      assert_equal "unavailable", oauth_app.proxima_availability
      refute_predicate oauth_app.marketplace_listing, :present?
    end
  end

  context "#copilot_model_validation" do
    test "allows listing with valid copilot_app value and valid listable_type" do
      integration = create :integration
      listing = build(:marketplace_listing, listable: integration, copilot_app: true)

      assert_predicate listing, :valid?
    end

    test "disallows listing with valid copilot_app value but invalid listable type" do
      oauth_app = create :oauth_application
      listing = build(:marketplace_listing, listable: oauth_app, copilot_app: true)

      refute listing.valid?
      assert_includes listing.errors[:base], "Only integrations can be marked as a copilot app"
    end
  end

  context "#verified_domains_list" do
    test "returns verified domains of owner org" do
      org = create(:business_plus_org)
      domain = create(:verifiable_domain, owner: org, verified: true)
      org.reload

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      query = <<-'GRAPHQL'
        query($id: ID!) {
          node(id: $id) {
            ... on MarketplaceListingOwner {
              verifiedDomainsList
            }
          }
      }
      GRAPHQL

      data = execute_query(query, :$id => listing.owner.global_relay_id).data
      assert_same_elements [domain.domain], data["node"]["verifiedDomainsList"]
    end

    test "includes verified domains of the owner org's parent enterprise" do
      org = create(:business_plus_org)
      business = create(:business, organizations: [org])
      domain = create(:verifiable_domain, owner: org, verified: true)
      business_domain = create(:verifiable_domain, owner: business, verified: true)
      org.reload

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      query = <<-'GRAPHQL'
        query($id: ID!) {
          node(id: $id) {
            ... on MarketplaceListingOwner {
              verifiedDomainsList
            }
          }
      }
      GRAPHQL

      data = execute_query(query, :$id => listing.owner.global_relay_id).data
      assert_same_elements \
        [domain.domain, business_domain.domain],
        data["node"]["verifiedDomainsList"]
    end

    test "returns empty list for orgs without verified domains" do
      org = create(:business_plus_org)
      create(:verifiable_domain, owner: org)    # unverified domain should not be returned

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      query = <<-'GRAPHQL'
        query($id: ID!) {
          node(id: $id) {
            ... on MarketplaceListingOwner {
              verifiedDomainsList
            }
          }
      }
      GRAPHQL

      data = execute_query(query, :$id => listing.owner.global_relay_id).data
      assert_empty data["node"]["verifiedDomainsList"]
    end

    test "returns empty list when owner is user" do
      user1 = create(:user)
      integration = create(:integration, owner: user1)
      listing = create(:marketplace_listing, listable: integration)

      query = <<-'GRAPHQL'
        query($id: ID!) {
          node(id: $id) {
            ... on MarketplaceListingOwner {
              verifiedDomainsList
            }
          }
      }
      GRAPHQL

      data = execute_query(query, :$id => listing.owner.global_relay_id).data

      assert_empty data["node"]["verifiedDomainsList"]
    end
  end

  context "#admins" do
    test "returns just the owner of OAuth app when owner is a user" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      assert_equal [user], listing.admins
    end

    test "returns just the owner of integration when owner is a user" do
      user = create(:user)
      integration = create(:integration, owner: user)
      listing = create(:marketplace_listing, listable: integration)

      assert_equal [user], listing.admins
    end

    test "returns admins of org owner of OAuth app" do
      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization, admin: user1)
      org.add_admin(user2)
      org.reload

      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      assert_same_elements [user1, user2], listing.admins
    end

    test "returns admins of org owner of integration" do
      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization, admin: user1)
      org.add_admin(user2)
      org.reload

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      assert_same_elements [user1, user2], listing.admins
    end
  end

  context "#partnership_managed?" do
    test "returns false when the action does not have any categories" do
      marketplace_listing = create(:marketplace_listing)

      refute marketplace_listing.partnership_managed?
    end

    test "returns false when the category is not github partners" do
      matching_category = create(:marketplace_category)
      marketplace_listing = create(:marketplace_listing, categories: [matching_category])

      refute marketplace_listing.partnership_managed?
    end

    test "returns true when the category is github partners" do
      matching_category = create(:marketplace_category, name: "Github Partners", slug: "github-partners")
      marketplace_listing = create(:marketplace_listing, categories: [matching_category])

      assert marketplace_listing.partnership_managed?
    end
  end


  context "#can_sign_end_user_agreement?" do
    test "true for verified listing with end-user agreement for user" do
      listing = create(:marketplace_listing, :verified)
      user = create(:user)
      agreement = create(:marketplace_agreement, :end_user)

      assert listing.can_sign_end_user_agreement?(user, agreement: agreement)
    end

    test "false when listing is draft" do
      listing = create(:marketplace_listing)
      user = create(:user)
      agreement = create(:marketplace_agreement, :end_user)

      refute_predicate listing, :verified?
      refute listing.can_sign_end_user_agreement?(user, agreement: agreement)
    end

    test "false when no user is given" do
      listing = create(:marketplace_listing, :verified)
      agreement = create(:marketplace_agreement, :end_user)

      refute listing.can_sign_end_user_agreement?(nil, agreement: agreement)
    end

    test "false when agreement is for integrators" do
      listing = create(:marketplace_listing, :verified)
      user = create(:user)
      agreement = create(:marketplace_agreement)

      assert_predicate agreement, :integrator?
      refute listing.can_sign_end_user_agreement?(user, agreement: agreement)
    end

    test "false when agreement is nil" do
      listing = create(:marketplace_listing, :verified)
      user = create(:user)

      refute listing.can_sign_end_user_agreement?(user, agreement: nil)
    end

    test "false when user has already signed given agreement" do
      listing = create(:marketplace_listing, :verified)
      user = create(:user)
      agreement = create(:marketplace_agreement, :end_user)
      create(:marketplace_agreement_signature, signatory: user, agreement: agreement)

      refute listing.can_sign_end_user_agreement?(user, agreement: agreement)
    end
  end

  context "#can_sign_integrator_agreement?" do
    test "true for listing with integrator agreement for listing admin" do
      listing = create(:marketplace_listing)
      agreement = create(:marketplace_agreement)

      assert listing.can_sign_integrator_agreement?(listing.owner, agreement: agreement)
    end

    test "false when listing is archived" do
      listing = create(:marketplace_listing, :archived)
      agreement = create(:marketplace_agreement)

      assert_predicate listing, :archived?
      refute listing.can_sign_integrator_agreement?(listing.owner, agreement: agreement)
    end

    test "false when no user is given" do
      listing = create(:marketplace_listing)
      agreement = create(:marketplace_agreement)

      refute listing.can_sign_integrator_agreement?(nil, agreement: agreement)
    end

    test "false when agreement is for end users" do
      listing = create(:marketplace_listing)
      agreement = create(:marketplace_agreement, :end_user)

      assert_predicate agreement, :end_user?
      refute listing.can_sign_integrator_agreement?(listing.owner, agreement: agreement)
    end

    test "false when agreement is nil" do
      listing = create(:marketplace_listing)

      refute listing.can_sign_integrator_agreement?(listing.owner, agreement: nil)
    end

    test "false when user has already signed given agreement" do
      listing = create(:marketplace_listing)
      agreement = create(:marketplace_agreement)
      create(:marketplace_agreement_signature, signatory: listing.owner, agreement: agreement)

      refute listing.can_sign_integrator_agreement?(listing.owner, agreement: agreement)
    end
  end

  context "state" do
    test "default state is draft" do
      listing = Marketplace::Listing.new

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?
    end

    test "touches updated_at upon successful state transition" do
      yesterday = 1.day.ago
      listing = T.let(nil, T.untyped)
      original_updated_at = T.let(nil, T.untyped)
      Timecop.freeze(yesterday) do
        org = create(:organization)
        integration = create(:integration, owner: org)
        listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration, updated_at: yesterday)
        original_updated_at = listing.updated_at

        assert_equal :draft, listing.current_state.name
        assert_equal yesterday.to_i, listing.updated_at.to_i
      end

      now = Time.current
      Timecop.freeze(now) do
        listing.request_verified_approval!(@user)

        refute_equal original_updated_at, listing.reload.updated_at
        assert_equal now.to_i, listing.updated_at.to_i
      end
    end

    test "does not touch updated_at upon invalid state transition" do
      listing = create(:marketplace_listing_ready_for_review, updated_at: 1.day.ago)
      original_updated_at = listing.updated_at.utc

      assert_equal :draft, listing.current_state.name

      assert_raises(Workflow::NoTransitionAllowed) { listing.reject! }
      assert_equal original_updated_at, listing.reload.updated_at.utc
    end

    test "does not transition from draft to rejected" do
      listing = create(:marketplace_listing)

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?

      assert_raises(Workflow::NoTransitionAllowed) { listing.reject! }
    end

    test "does not transition from draft to verified" do
      listing = create(:marketplace_listing)

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?

      assert_raises(Workflow::NoTransitionAllowed) { listing.approve! }
    end

    test "transitions from draft to verification_pending_from_draft" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration)

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?

      listing.request_verified_approval!(@user)

      assert_equal :verification_pending_from_draft, listing.current_state.name
      refute_predicate listing, :draft?
      assert_predicate listing, :verification_pending_from_draft?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :draft,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verification_pending_from_draft, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "does not transition from draft to verification_pending_from_draft when missing required fields" do
      listing = create(:marketplace_listing_ready_for_review, security_email: nil)

      assert_predicate listing, :draft?

      assert_raises Workflow::NoTransitionAllowed do
        listing.request_verified_approval!(@user)
      end

      assert_predicate listing, :draft?
      refute_predicate listing, :verification_pending_from_draft?
    end

    test "transitions from draft to unverified_pending" do
      listing = create(:marketplace_listing_ready_for_unverified_review)

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?

      listing.request_unverified_approval!(@user)

      assert_equal :unverified_pending, listing.current_state.name
      refute_predicate listing, :draft?
      assert_predicate listing, :unverified_pending?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :draft,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :unverified_pending, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "does not transition from draft to unverified_pending when missing required fields" do
      listing = create(:marketplace_listing_ready_for_unverified_review, security_email: nil)

      assert_predicate listing, :draft?

      assert_raises Workflow::NoTransitionAllowed do
        listing.request_unverified_approval!(@user)
      end

      assert_predicate listing, :draft?
      refute_predicate listing, :unverified_pending?
    end

    test "does not transition from draft to unverified_pending when has a paid, published plan" do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      create(:marketplace_listing_plan, :paid, :published, listing: listing)

      assert_predicate listing, :draft?

      assert_raises Workflow::NoTransitionAllowed do
        listing.request_unverified_approval!(@user)
      end

      assert_predicate listing, :draft?
      refute_predicate listing, :unverified_pending?
    end

    test "transitions from unverified_pending to draft" do
      listing = create(:marketplace_listing, :unverified_pending)

      assert_equal :unverified_pending, listing.current_state.name
      assert_predicate listing, :unverified_pending?

      listing.redraft!(@admin)

      assert_equal :draft, listing.current_state.name
      refute_predicate listing, :unverified_pending?
      assert_predicate listing, :draft?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :unverified_pending,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :draft, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from unverified_pending to unverified" do
      listing = create(:marketplace_listing, :unverified_pending)

      assert_equal :unverified_pending, listing.current_state.name
      assert_predicate listing, :unverified_pending?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve!(@admin)

      assert_equal :unverified, listing.current_state.name
      refute_predicate listing, :unverified_pending?
      assert_predicate listing, :unverified?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :unverified_pending,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :unverified, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from unverified to archived" do
      listing = create(:marketplace_listing, :unverified)

      assert_equal :unverified, listing.current_state.name
      assert_predicate listing, :unverified?

      listing.delist!(@admin)

      assert_equal :archived, listing.current_state.name
      refute_predicate listing, :unverified?
      assert_predicate listing, :archived?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :unverified,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :archived, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from unverified to verification_pending_from_unverified" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, :unverified, :verified_publisher, listable: integration)

      assert_equal :unverified, listing.current_state.name
      assert_predicate listing, :unverified?

      listing.request_verified_approval!(@admin)

      assert_equal :verification_pending_from_unverified, listing.current_state.name
      refute_predicate listing, :unverified?
      assert_predicate listing, :verification_pending_from_unverified?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :unverified,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verification_pending_from_unverified, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "does not transition from unverified to verification_pending_from_unverified when missing required fields" do
      listing = create(:marketplace_listing_ready_for_review, :unverified, security_email: nil)

      assert_predicate listing, :unverified?

      assert_raises Workflow::NoTransitionAllowed do
        listing.request_verified_approval!(@admin)
      end

      assert_predicate listing, :unverified?
      refute_predicate listing, :verification_pending_from_unverified?
    end

    test "transitions from verification_pending_from_unverified to verified" do
      listing = create(:marketplace_listing, :verification_pending_from_unverified)

      assert_equal :verification_pending_from_unverified, listing.current_state.name
      assert_predicate listing, :verification_pending_from_unverified?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve!(@admin)

      assert_equal :verified, listing.current_state.name
      refute_predicate listing, :verification_pending_from_unverified?
      assert_predicate listing, :verified?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verification_pending_from_unverified,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verified, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from verification_pending_from_unverified to verified creator" do
      listing = create(:marketplace_listing, :verification_pending_from_unverified)

      assert_equal :verification_pending_from_unverified, listing.current_state.name
      assert_predicate listing, :verification_pending_from_unverified?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve_creator!(@admin)

      assert_equal :verified_creator, listing.current_state.name
      refute_predicate listing, :verification_pending_from_unverified?
      assert_predicate listing, :verified_creator?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verification_pending_from_unverified,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verified_creator, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from verification_pending_from_draft to rejected" do
      listing = create(:marketplace_listing, state: 1)
      assert_equal :verification_pending_from_draft, listing.current_state.name
      assert_predicate listing, :verification_pending_from_draft?

      listing.reject!(@admin)

      assert_equal :rejected, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :rejected?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verification_pending_from_draft,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :rejected, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from verification_pending_from_draft to verified" do
      listing = create(:marketplace_listing, state: 1)

      assert_equal :verification_pending_from_draft, listing.current_state.name
      assert_predicate listing, :verification_pending_from_draft?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve!(@admin)

      assert_equal :verified, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :verified?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verification_pending_from_draft,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verified, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from verification_pending_from_draft to verified creator" do
      listing = create(:marketplace_listing, state: 1)

      assert_equal :verification_pending_from_draft, listing.current_state.name
      assert_predicate listing, :verification_pending_from_draft?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve_creator!(@admin)

      assert_equal :verified_creator, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :verified_creator?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verification_pending_from_draft,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verified_creator, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "clears out subscription items when transitioned from draft to unverified_pending" do
      listing       = create(:marketplace_listing_ready_for_unverified_review, :draft)
      plan          = create :marketplace_listing_plan, :free, :published, listing: listing
      item          = create :billing_subscription_item, subscribable: plan, quantity: 1
      other_listing_item = create :billing_subscription_item

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?

      listing.request_unverified_approval!

      assert_equal :unverified_pending, listing.current_state.name

      assert_raises ActiveRecord::RecordNotFound do
        item.reload
      end

      assert other_listing_item.reload, "items belonging to other listing are not removed during approval"
    end

    test "clears out subscription items when transitioned from unverified_pending to unverified" do
      listing       = create(:marketplace_listing, :unverified_pending)
      plan          = create :marketplace_listing_plan, :published, listing: listing
      item          = create :billing_subscription_item, subscribable: plan, quantity: 1
      other_listing_item = create :billing_subscription_item

      assert_equal :unverified_pending, listing.current_state.name

      listing.approve!

      assert_equal :unverified, listing.current_state.name

      assert_raises ActiveRecord::RecordNotFound do
        item.reload
      end

      assert other_listing_item.reload, "items belonging to other listing are not removed during approval"
    end

    test "clears out subscription items when transitioned from draft to verification_pending_from_draft" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing       = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration)
      plan          = create :marketplace_listing_plan, :published, listing: listing
      item          = create :billing_subscription_item, subscribable: plan, quantity: 1
      other_listing_item = create :billing_subscription_item

      assert_equal :draft, listing.current_state.name
      assert_predicate listing, :draft?

      listing.request_verified_approval!

      assert_equal :verification_pending_from_draft, listing.current_state.name
      refute_predicate listing, :draft?
      assert_predicate listing, :verification_pending_from_draft?

      assert_raises ActiveRecord::RecordNotFound do
        item.reload
      end

      assert other_listing_item.reload, "items belonging to other listing are not removed during approval"
    end

    test "clears out subscription items when transitioned from verification_pending_from_draft to verified" do
      listing       = create(:marketplace_listing, :verification_pending_from_draft)
      plan          = create :marketplace_listing_plan, :published, listing: listing
      item          = create :billing_subscription_item, subscribable: plan, quantity: 1
      other_listing_item = create :billing_subscription_item

      assert_equal :verification_pending_from_draft, listing.current_state.name
      assert_predicate listing, :verification_pending_from_draft?

      listing.approve!

      assert_equal :verified, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :verified?

      assert_raises ActiveRecord::RecordNotFound do
        item.reload
      end

      assert other_listing_item.reload, "items belonging to other listing are not removed during approval"
    end

    test "does not clear out subscription items when transitioned from archived to verified" do
      listing       = create(:marketplace_listing, :archived)
      plan          = create :marketplace_listing_plan, :published, listing: listing
      item          = create :billing_subscription_item, subscribable: plan, quantity: 1

      assert_equal :archived, listing.current_state.name
      assert_predicate listing, :archived?

      listing.approve!

      assert_equal :verified, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :verified?

      assert item.reload, "items are not removed during invalid state to verified"
    end


    test "does not clear out subscription items when transitioned from archived to verified creator" do
      listing       = create(:marketplace_listing, :archived)
      plan          = create :marketplace_listing_plan, :published, listing: listing
      item          = create :billing_subscription_item, subscribable: plan, quantity: 1

      assert_equal :archived, listing.current_state.name
      assert_predicate listing, :archived?

      listing.approve_creator!

      assert_equal :verified_creator, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :verified_creator?

      assert item.reload, "items are not removed during invalid state to verified creator"
    end

    test "transitions from verification_pending_from_draft to draft" do
      listing = create(:marketplace_listing, state: 1)

      assert_equal :verification_pending_from_draft, listing.current_state.name
      assert_predicate listing, :verification_pending_from_draft?

      listing.redraft!(@admin)

      assert_equal :draft, listing.current_state.name
      refute_predicate listing, :verification_pending_from_draft?
      assert_predicate listing, :draft?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verification_pending_from_draft,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :draft, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from verified to archived" do
      listing = create(:marketplace_listing, state: 3)

      assert_equal :verified, listing.current_state.name
      assert_predicate listing, :verified?

      listing.delist!(@admin)

      assert_equal :archived, listing.current_state.name
      refute_predicate listing, :verified?
      assert_predicate listing, :archived?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verified,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :archived, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from verified creator to archived" do
      listing = create(:marketplace_listing, state: 8)

      assert_equal :verified_creator, listing.current_state.name
      assert_predicate listing, :verified_creator?

      listing.delist!(@admin)

      assert_equal :archived, listing.current_state.name
      refute_predicate listing, :verified_creator?
      assert_predicate listing, :archived?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :verified_creator,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :archived, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from archived to verified" do
      listing = create(:marketplace_listing, state: 4)

      assert_equal :archived, listing.current_state.name
      assert_predicate listing, :archived?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve!(@admin)

      assert_equal :verified, listing.current_state.name
      refute_predicate listing, :archived?
      assert_predicate listing, :verified?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :archived,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verified, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end

    test "transitions from archived to verified creator" do
      listing = create(:marketplace_listing, state: 4)

      assert_equal :archived, listing.current_state.name
      assert_predicate listing, :archived?

      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)
      listing.approve_creator!(@admin)

      assert_equal :verified_creator, listing.current_state.name
      refute_predicate listing, :archived?
      assert_predicate listing, :verified_creator?

      unless GitHub.enterprise?
        assert_hydro_messages(count: 1, schema: "github.marketplace.v0.ListingStateChange")
        assert_hydro_published({
          marketplace_listing: Hydro::EntitySerializer.marketplace_listing(listing),
          previous_state: :archived,
        }, schema: "github.marketplace.v0.ListingStateChange")
        assert_equal :verified_creator, Hydro::EntitySerializer.marketplace_listing(listing)[:current_state].to_sym
      end
    end


    test "updates category counter caches on transition to verified" do
      primary_category = create(
        :marketplace_category,
        primary_listing_count:   1,
        secondary_listing_count: 1,
      )

      secondary_category = create(
        :marketplace_category,
        primary_listing_count: 1,
        secondary_listing_count: 1,
      )

      inverted_listing = create(
        :marketplace_listing,
        :verification_pending_from_draft,
        categories: [secondary_category, primary_category],
      )

      listing = create(
        :marketplace_listing,
        :verification_pending_from_draft,
        categories: [primary_category, secondary_category],
      )

      assert_equal 1, primary_category.primary_listing_count
      assert_equal 1, primary_category.secondary_listing_count
      assert_equal 1, secondary_category.primary_listing_count
      assert_equal 1, secondary_category.secondary_listing_count

      listing.approve!
      primary_category.reload
      secondary_category.reload

      assert_equal 2, primary_category.primary_listing_count
      assert_equal 1, primary_category.secondary_listing_count
      assert_equal 1, secondary_category.primary_listing_count
      assert_equal 2, secondary_category.secondary_listing_count

      inverted_listing.approve!
      primary_category.reload
      secondary_category.reload

      assert_equal 2, primary_category.primary_listing_count
      assert_equal 2, primary_category.secondary_listing_count
      assert_equal 2, secondary_category.primary_listing_count
      assert_equal 2, secondary_category.secondary_listing_count
    end

    test "increments category counters when listing is approved as unverified" do
      primary_category = create(:marketplace_category, primary_listing_count: 1)
      secondary_category = create(:marketplace_category, secondary_listing_count: 0)
      listing = create(
        :marketplace_listing,
        :unverified_pending,
        categories: [primary_category, secondary_category],
      )

      assert_equal 1, primary_category.primary_listing_count
      assert_equal 0, secondary_category.secondary_listing_count

      listing.approve!

      assert_equal 2, primary_category.reload.primary_listing_count
      assert_equal 1, secondary_category.reload.secondary_listing_count
    end

    test "decrements category counters when listing is delisted from unverified" do
      primary_category = create(:marketplace_category, primary_listing_count: 1)
      secondary_category = create(:marketplace_category, secondary_listing_count: 1)
      listing = create(
        :marketplace_listing,
        :unverified,
        categories: [primary_category, secondary_category],
      )

      assert_equal 1, primary_category.primary_listing_count
      assert_equal 1, secondary_category.secondary_listing_count

      listing.delist!

      assert_equal 0, primary_category.reload.primary_listing_count
      assert_equal 0, secondary_category.reload.secondary_listing_count
    end

    test "does not change category counters if listing changes state but still publicly listed" do
      primary_category = create(:marketplace_category, primary_listing_count: 1)
      secondary_category = create(:marketplace_category, secondary_listing_count: 1)

      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(
        :marketplace_listing_ready_for_review,
        :verified_publisher,
        :unverified,
        listable: integration,
        categories: [primary_category, secondary_category],
      )

      assert_equal 1, primary_category.primary_listing_count
      assert_equal 1, secondary_category.secondary_listing_count

      listing.request_verified_approval!(@user)

      assert_equal 1, primary_category.reload.primary_listing_count
      assert_equal 1, secondary_category.reload.secondary_listing_count

      listing.approve!

      assert_equal 1, primary_category.reload.primary_listing_count
      assert_equal 1, secondary_category.reload.secondary_listing_count
    end

    test "adjusts category counters when listing is publicly listed but categories changed" do
      original_primary_category = create(:marketplace_category, primary_listing_count: 1)
      new_primary_category = create(:marketplace_category, primary_listing_count: 0)
      listing = create(
        :marketplace_listing,
        :verification_pending_from_unverified,
        categories: [original_primary_category],
      )

      assert_equal 1, original_primary_category.primary_listing_count
      assert_equal 0, new_primary_category.primary_listing_count

      listing.skip_draft_validation = true
      listing.categories = [new_primary_category]

      assert_equal 0, original_primary_category.reload.primary_listing_count
      assert_equal 1, new_primary_category.reload.primary_listing_count
    end

    test "updates search when fields are updated on verified listing" do
      listing = create(:marketplace_listing, state: :verified)
      Search.expects(:add_to_search_index).with("marketplace_listing", listing.id)

      listing.update(short_description: "new desc")
    end

    test "updates category counter caches on transition from verified" do
      primary_category = create(
        :marketplace_category,
        primary_listing_count:   1,
        secondary_listing_count: 1,
      )

      secondary_category = create(
        :marketplace_category,
        primary_listing_count: 1,
        secondary_listing_count: 1,
      )

      inverted_listing = create(
        :marketplace_listing,
        :verified,
        categories: [secondary_category, primary_category],
      )

      listing = create(
        :marketplace_listing,
        :verified,
        categories: [primary_category, secondary_category],
      )

      assert_equal 1, primary_category.primary_listing_count
      assert_equal 1, primary_category.secondary_listing_count
      assert_equal 1, secondary_category.primary_listing_count
      assert_equal 1, secondary_category.secondary_listing_count

      listing.delist!
      primary_category.reload
      secondary_category.reload

      assert_equal 0, primary_category.primary_listing_count
      assert_equal 1, primary_category.secondary_listing_count
      assert_equal 1, secondary_category.primary_listing_count
      assert_equal 0, secondary_category.secondary_listing_count

      inverted_listing.delist!
      primary_category.reload
      secondary_category.reload

      assert_equal 0, primary_category.primary_listing_count
      assert_equal 0, primary_category.secondary_listing_count
      assert_equal 0, secondary_category.primary_listing_count
      assert_equal 0, secondary_category.secondary_listing_count
    end

    test "removes from search when delisted" do
      listing = create(:marketplace_listing, :verified)

      assert_enqueued_with job: RemoveFromSearchIndexJob do
        listing.delist!
      end
    end

    test "can preload categories" do
      regular_cats = create_list(:marketplace_category, 2)
      filter_cats = create_list(:marketplace_category, 2, acts_as_filter: true)
      categories = regular_cats + filter_cats

      listing = create(:marketplace_listing, :verified, categories: categories)

      table_name = Marketplace::Listing.table_name
      relation = Marketplace::Listing.
        where("#{table_name}.id > 0").
        order("#{table_name}.id ASC").
        limit(10).
        includes(:categories)

      listings = relation.to_a

      assert listings.size > 0, "expected one listing to be returned"
      assert_equal listing, listings.last
    end

    test "can preload regular categories" do
      regular_cats = create_list(:marketplace_category, 2)
      filter_cats = create_list(:marketplace_category, 2, acts_as_filter: true)
      categories = regular_cats + filter_cats

      listing = create(:marketplace_listing, :verified, categories: categories)

      table_name = Marketplace::Listing.table_name
      relation = Marketplace::Listing.
        where("#{table_name}.id > 0").
        order("#{table_name}.id ASC").
        limit(10).
        includes(:regular_categories)

      listings = relation.to_a

      assert listings.size > 0, "expected one listing to be returned"
      assert_equal listing, listings.last
    end

    test "can preload filter categories" do
      regular_cats = create_list(:marketplace_category, 2)
      filter_cats = create_list(:marketplace_category, 2, acts_as_filter: true)
      categories = regular_cats + filter_cats

      listing = create(:marketplace_listing, :verified, categories: categories)

      table_name = Marketplace::Listing.table_name
      relation = Marketplace::Listing.
        where("#{table_name}.id > 0").
        order("#{table_name}.id ASC").
        limit(10).
        includes(:filter_categories)

      listings = relation.to_a

      assert listings.size > 0, "expected one listing to be returned"
      assert_equal listing, listings.last
    end
  end

  test "does not change category counter caches when category changes for draft listing" do
    old_category = create(:marketplace_category, primary_listing_count: 0)
    new_category = create(:marketplace_category, primary_listing_count: 0)

    listing = create(:marketplace_listing, categories: [old_category])

    assert_predicate listing, :draft?
    assert_no_difference ["old_category.reload.primary_listing_count",
                          "new_category.reload.primary_listing_count"] do

      listing.categories = [new_category]
      listing.save!
    end
  end

  test "updates category counter caches when changing a verified listing's categories" do
    primary_category = create(
      :marketplace_category,
      primary_listing_count:   1,
      secondary_listing_count: 1,
    )

    secondary_category = create(
      :marketplace_category,
      primary_listing_count:   1,
      secondary_listing_count: 1,
    )

    new_primary_category = create(:marketplace_category)

    draft_listing = create(
      :marketplace_listing,
      state:      :draft,
      categories: [primary_category, secondary_category],
    )

    verified_inverted_listing = create(
      :marketplace_listing,
      state:      :verified,
      categories: [secondary_category, primary_category],
    )

    verified_listing = create(
      :marketplace_listing,
      state:      :verified,
      categories: [primary_category, secondary_category],
    )

    assert_equal 2, verified_listing.categories.reload.count
    assert_equal 0, new_primary_category.primary_listing_count
    assert_equal 1, primary_category.primary_listing_count
    assert_equal 1, primary_category.secondary_listing_count
    assert_equal 1, secondary_category.primary_listing_count
    assert_equal 1, secondary_category.secondary_listing_count

    verified_listing.skip_draft_validation = true
    verified_listing.categories = [new_primary_category]

    new_primary_category.reload
    primary_category.reload
    secondary_category.reload

    assert_equal 1, verified_listing.categories.reload.count
    assert_equal 1, new_primary_category.reload.primary_listing_count
    assert_equal 0, primary_category.primary_listing_count
    assert_equal 1, primary_category.secondary_listing_count
    assert_equal 1, secondary_category.primary_listing_count
    assert_equal 0, secondary_category.secondary_listing_count
  end

  context "validations" do
    test "disallows listing a private integration" do
      integration = create(:integration, public: false)
      listing = build(:marketplace_listing, listable: integration)

      assert_predicate integration, :private?
      refute_predicate listing, :valid?
      assert_includes listing.errors[:integration], "must be public"
    end

    # https://github.com/github/github/issues/73083
    test "disallows owner's email to start with support@ if owned by a user" do
      user = create(:user)
      user.update_attribute(:email, "support@example.com")
      app = create(:oauth_application, user: user)
      listing = build(:marketplace_listing, listable: app)

      assert_equal [user], listing.admins
      refute_predicate listing, :valid?
      assert_includes listing.errors[:base],
        "At least one admin for the listing must have an email address that does not start with " +
        "'support@'."
    end

    # https://github.com/github/github/issues/73083
    test "requires at least one org admin email to not start with support@ if owned by an org" do
      admin1 = create(:user, email: "support@example.com")
      admin2 = create(:user, email: "support@domain.com")
      org = create(:organization, admin: admin1)
      org.add_admin(admin2)
      org.reload
      app = create(:oauth_application, user: org)
      listing = build(:marketplace_listing, listable: app)

      assert_same_elements [admin1, admin2], listing.admins
      refute_predicate listing, :valid?
      assert_includes listing.errors[:base],
        "At least one admin for the listing must have an email address that does not start with " +
        "'support@'."
    end

    test "requires a primary_category on create" do
      listing = build(:marketplace_listing, categories: [])

      refute_predicate listing, :valid?, "should not be valid without a primary category URL"
    end

    test "requires a name on create" do
      listing = build(:marketplace_listing, name: nil)

      refute_predicate listing, :valid?, "should not be valid without a name set"
      assert_predicate listing.errors[:name], :any?, "should require name is set"
    end

    [:short_description, :full_description, :privacy_policy_url, :support_url].each do |attr|
      test "requires a #{attr} to progress beyond a draft listing" do
        listing = build(:marketplace_listing, state: :verified)
        listing.send(:write_attribute, attr, nil)

        refute_predicate listing, :valid?, "should not be valid without a #{attr}"
        assert_predicate listing.errors[attr], :any?, "should require a #{attr}"
      end
    end

    test "requires an installation_url when integratable is an OAuth app" do
      listing = build(:marketplace_listing, state: :verified, listable: create(:oauth_application))
      listing.installation_url = nil

      refute_predicate listing, :valid?, "should not be valid without an installation URL"
    end

    test "does not require an installation_url when integratable is an integration" do
      listing = build(:marketplace_listing, :integration)
      listing.installation_url = nil

      assert_predicate listing, :valid?
    end

    test "disallows setting categories when listing is not a draft" do
      listing = create(:marketplace_listing, :verified)
      listing.categories = [create(:marketplace_category)]
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:categories], :any?
    end

    test "disallows adding more than the maximum number of supported languages" do
      Marketplace::Listing.stub_const(:MAX_SUPPORTED_LANGUAGES_COUNT, 1) do
        languages = create_list(:language_name, 2)
        listing = Marketplace::Listing.new(languages: languages)

        refute_predicate listing, :valid?
        listing_errors = listing.errors.messages[:listing]
        assert_equal(["has reached its limit for supported languages"], listing_errors)
      end
    end

    test "disallows adding more than the maximum number of featured organizations" do
      Marketplace::Listing.stub_const(:MAX_FEATURED_ORGANIZATIONS_COUNT, 1) do
        listing = create(:marketplace_listing)
        listing.featured_organizations << create_list(:marketplace_listing_featured_organization, 2)

        refute_predicate listing, :valid?
        listing_errors = listing.errors.messages[:listing]
        assert_equal(["has reached its limit for featured organizations"], listing_errors)
      end
    end

    test "disallows featuring an draft listing" do
      listing = create(:marketplace_listing, :draft, :with_hero_card)

      listing.featured_at = Time.zone.now

      refute_predicate listing, :valid?
      listing_errors = listing.errors.messages[:featured_at]
      assert_equal(["cannot be featured since the listing is not verified"], listing_errors)
    end

    test "allows featuring an verified listing" do
      listing = create(:marketplace_listing, :verified, :with_hero_card)
      listing.featured_at = Time.zone.now

      assert listing.valid?
    end

    test "disallows invalid email contacts" do
      listing = build(:marketplace_listing,
        technical_email: "not_an_email",
        finance_email: "notemail",
        marketing_email: "nothing",
        security_email: "wat",
      )

      refute_predicate listing, :valid?

      assert_equal(["does not look like an email address"], listing.errors.messages[:technical_email])
      assert_equal(["does not look like an email address"], listing.errors.messages[:marketing_email])
      assert_equal(["does not look like an email address"], listing.errors.messages[:finance_email])
      assert_equal(["does not look like an email address"], listing.errors.messages[:security_email])
    end

    test "disallows featuring an verified listing without a hero card image" do
      listing = create(:marketplace_listing, :verified, hero_card_background_image: nil)
      listing.featured_at = Time.zone.now

      refute_predicate listing, :valid?
      listing_errors = listing.errors.messages[:featured_at]
      assert_equal(["cannot be featured since the listing does not have a hero card background"], listing_errors)
    end

    test "requires a valid hex color code for background color" do
      listing = Marketplace::Listing.new(bgcolor: "ff")
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:bgcolor], :any?, "should require a valid hex color code"
    end

    test "requires unique categories" do
      category = create(:marketplace_category)
      listing = build(:marketplace_listing, categories: [category, category])

      refute_predicate listing, :valid?
      assert_predicate listing.errors[:categories], :any?,
        "should require a different secondary category from the primary category"
    end

    test "disallows duplicate listing for an OAuth app" do
      listing1 = create(:marketplace_listing)
      listing2 = Marketplace::Listing.new(listable: listing1.listable)
      refute_predicate listing2, :valid?
      assert_predicate listing2.errors[:listable], :any?,
        "should require a different OAuth app"
    end

    test "disallows duplicate listing for an integration" do
      listing1 = create(:marketplace_listing, :integration)
      listing2 = build(:marketplace_listing, listable: listing1.listable)
      refute_predicate listing2, :valid?
      assert_predicate listing2.errors[:listable], :any?,
        "should require a different integration"
    end

    test "allows listable with same ID and different types" do
      listing1 = create(:marketplace_listing)
      if (integration = Integration.find_by(id: listing1.listable_id)).nil?
        integration = create(:integration)
        integration.update!(id: listing1.id)
      end

      listing2 = build(:marketplace_listing, listable: integration)
      assert_predicate listing2, :valid?
    end

    test "name must be unique (case insensitive)" do
      existing_listing = create(:marketplace_listing)
      new_listing = build(:marketplace_listing)
      new_listing.name = existing_listing.name
      refute_predicate new_listing, :valid?, "should not be valid with a duplicate name"
      assert_predicate new_listing.errors[:name], :any?, "should require a unique name"

      new_listing.name = existing_listing.name.upcase
      refute_predicate new_listing, :valid?, "should not be valid with a duplicate name"
      assert_predicate new_listing.errors[:name], :any?, "should require a unique name"
    end

    test "slug must be unique (case insensitive)" do
      existing_listing = create(:marketplace_listing)
      new_listing = build(:marketplace_listing)
      new_listing.name = existing_listing.name
      refute_predicate new_listing, :valid?, "should not be valid with a duplicate slug"
      assert_predicate new_listing.errors[:slug], :any?, "should require a unique slug"

      new_listing.name = existing_listing.name.upcase
      refute_predicate new_listing, :valid?, "should not be valid with a duplicate slug"
      assert_predicate new_listing.errors[:slug], :any?, "should require a unique slug"
    end

    test "validates length of name" do
      text = "a" * (Marketplace::Listing::NAME_MAX_LENGTH + 1)
      listing = build(:marketplace_listing, name: text)

      refute_predicate listing, :valid?
      assert_predicate listing.errors[:name], :any?
    end

    test "validates length of full_description" do
      text = "a" * (Marketplace::Listing::FULL_DESCRIPTION_MAX_LENGTH + 1)
      listing = build(:marketplace_listing, full_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:full_description], :any?
    end

    test "validates length of short_description" do
      text = "a" * (Marketplace::Listing::SHORT_DESCRIPTION_MAX_LENGTH + 1)
      listing = build(:marketplace_listing, short_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:short_description], :any?
    end

    test "validates length of extended_description" do
      text = "a" * (Marketplace::Listing::EXTENDED_DESCRIPTION_MAX_LENGTH + 1)
      listing = build(:marketplace_listing, extended_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:extended_description], :any?
    end

    test "validates length of categories" do
      listing_with_no_categories = build(:marketplace_listing, categories: [])

      refute_predicate listing_with_no_categories, :valid?
      assert_predicate listing_with_no_categories.errors[:categories], :any?
    end

    test "validates length of regular categories" do
      category = create(:marketplace_category, acts_as_filter: true)
      listing_with_filters_only = build(:marketplace_listing, categories: [category])

      refute_predicate listing_with_filters_only, :valid?
      assert_predicate listing_with_filters_only.errors[:categories], :any?
    end

    test "short_description cannot end with a period" do
      text = "This app solves all of your problems."
      listing = build(:marketplace_listing, short_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:short_description], :any?
    end

    test "short_description cannot end with an exclamation point" do
      text = "This app solves all of your problems!"
      listing = build(:marketplace_listing, short_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:short_description], :any?
    end

    test "short_description cannot end with a question mark" do
      text = "This app solves all of your problems?"
      listing = build(:marketplace_listing, short_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:short_description], :any?
    end

    test "short_description adding a space does not circumvent punctuation validation" do
      text = "This app solves all of your problems? "
      listing = build(:marketplace_listing, short_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:short_description], :any?
    end

    test "short_description cannot include emojis" do
      text = "🐹"
      listing = build(:marketplace_listing, short_description: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:short_description], :any?
    end

    test "name cannot include emojis" do
      text = "🐹"
      listing = build(:marketplace_listing, name: text)
      refute_predicate listing, :valid?
      assert_predicate listing.errors[:name], :any?
    end

    test "support_url must be a valid email address" do
      listing = build(:marketplace_listing, support_url: "support@example.com")

      assert_predicate listing, :valid?
    end

    test "support_url cannot be an invalid email address" do
      listing = build(:marketplace_listing, support_url: "support")

      refute_predicate listing, :valid?
      assert_predicate listing.errors[:support_url], :any?
    end

    test "must own hero_image to set hero_image id" do
      # You can't set the hero image to an image that the listing doesn't own.
      foreign_listing = create(:marketplace_listing, :with_hero_card)
      listing = create(:marketplace_listing)
      listing.hero_card_background_image = foreign_listing.hero_card_background_image

      refute_predicate listing, :valid?
      assert_predicate listing.errors[:hero_card_background_image], :any?
    end

    [
      :company_url, :documentation_url, :pricing_url, :privacy_policy_url, :status_url,
      :support_url, :tos_url, :installation_url, :learn_more_url
    ].each do |url|
      test "#{url} requires a valid HTTP protocol" do
        listing = build(:marketplace_listing)
        assert_predicate listing, :valid?, "Unmodified test listing should be valid"

        listing.send(:write_attribute, url, "www.example.com")
        refute_predicate listing, :valid?, "a #{url} value should require an HTTP protocol"
        assert_predicate listing.errors[url], :any?, "should have a #{url} error"

        listing.send(:write_attribute, url, "http.www.example.com")
        refute_predicate listing, :valid?,
          "a #{url} value should require a properly formatted HTTP protocol"
        assert_predicate listing.errors[url], :any?, "should have a #{url} error"

        listing.send(:write_attribute, url, "http://www.example.com/my/#{url}")
        assert_predicate listing, :valid?, "#{url} should be valid with an http:// protocol"
        refute_predicate listing.errors[url], :any?, "should not have a #{url} error"

        listing.send(:write_attribute, url, "https://www.example.com/my/#{url}")
        assert_predicate listing, :valid?, "#{url} should be valid with an https:// protocol"
        refute_predicate listing.errors[url], :any?, "should not have a #{url} error"
      end
    end
  end

  context "#offers_free_trial?" do
    test "true when listing has a published plan offering a free trial" do
      plan = create(:marketplace_listing_plan, :free_trial)

      assert_predicate plan.listing, :offers_free_trial?
    end

    test "false when listing has a retired plan offering a free trial" do
      plan = create(:marketplace_listing_plan, :retired, has_free_trial: true)

      refute_predicate plan.listing, :offers_free_trial?
    end

    test "false when listing has a published plan that does not offer a free trial" do
      plan = create(:marketplace_listing_plan, :published, has_free_trial: false)

      refute_predicate plan.listing, :offers_free_trial?
    end
  end

  context "#published_free_plans?" do
    test "returns true if the listing has any published, free plans" do
      plan = create(:marketplace_listing_plan, :free)

      assert_predicate plan.listing, :published_free_plans?
    end

    test "returns false when the listing has free plans but they're not published" do
      plan = create(:marketplace_listing_plan, :free, :draft)

      refute_predicate plan.listing, :published_free_plans?
    end

    test "returns false when the listing doesn't have any free plans" do
      plan = create(:marketplace_listing_plan, :paid)

      refute_predicate plan.listing, :published_free_plans?
    end
  end

  context "scopes" do
    test "with_free_trial" do
      free_trial_listing_plan = create(:marketplace_listing_plan, :verified_listing, has_free_trial: true)
      free_trial_listing = free_trial_listing_plan.listing
      create(:marketplace_listing, :verified)

      assert_equal [free_trial_listing], Marketplace::Listing.with_free_trial

      # does not include duplicate listings when they have multiple free trial listing plans
      create(:marketplace_listing_plan, :verified_listing, :free_trial, listing: free_trial_listing)
      assert_equal [free_trial_listing], Marketplace::Listing.with_free_trial
    end

    test "with_state" do
      verified = create(:marketplace_listing, :verified)
      archived = create(:marketplace_listing, :archived)
      draft = create(:marketplace_listing, :draft)
      verification_pending_from_draft = create(:marketplace_listing, :verification_pending_from_draft)

      assert_equal [verified], Marketplace::Listing.with_state("verified")
      assert_equal [archived], Marketplace::Listing.with_state("archived")
      assert_equal [draft], Marketplace::Listing.with_state("draft")
      assert_equal [verification_pending_from_draft], Marketplace::Listing.with_state("verification_pending_from_draft")
    end

    test "with_states accepts multiple states" do
      draft = create(:marketplace_listing, :draft)
      verified = create(:marketplace_listing, :verified)
      unverified = create(:marketplace_listing, :unverified)

      assert_equal [verified, unverified], Marketplace::Listing.with_states(%w[verified unverified])
    end

    test "with_states accepts no states" do
      draft = create(:marketplace_listing, :draft)
      verified = create(:marketplace_listing, :verified)
      unverified = create(:marketplace_listing, :unverified)

      assert_equal [], Marketplace::Listing.with_states([])
    end

    test "with_category" do
      cat1 = create(:marketplace_category, name: "Foo")
      cat2 = create(:marketplace_category, name: "Bar")

      listing1 = create(:marketplace_listing, categories: [cat1, cat2])
      listing2 = create(:marketplace_listing, categories: [cat2])

      # Should include listing1 (secondary) and listing2 (primary)
      listings = Marketplace::Listing.with_category(cat2.slug)

      assert_same_elements listings, [listing1, listing2]
    end

    test "with_category, primary category only" do
      cat1 = create(:marketplace_category, name: "Foo")
      cat2 = create(:marketplace_category, name: "Bar")

      listing1 = create(:marketplace_listing, categories: [cat1, cat2])
      listing2 = create(:marketplace_listing, categories: [cat2])

      # Should only include listing2 (primary)
      listings = Marketplace::Listing.with_category(cat2.slug, primary_category_only: true)

      assert_same_elements listings, [listing2]
    end

    test "with_category returns subcategory listings too" do
      category = create("marketplace_category")
      subcategory = create("marketplace_category", parent_category: category)

      assert_equal subcategory.id, category.reload.sub_categories.first.id
      assert_equal category.id, subcategory.reload.parent_category_id

      listing_with_parent = create(:marketplace_listing, categories: [category])
      listing_with_subcategory = create(:marketplace_listing, categories: [subcategory])

      subcategory_listings = Marketplace::Listing.with_category(subcategory.slug)

      assert_same_elements subcategory_listings, [listing_with_subcategory]

      parent_category_listings = Marketplace::Listing.with_category(category.slug)

      assert_same_elements parent_category_listings, [listing_with_parent, listing_with_subcategory]
    end

    test "with_category returns distinct listings" do
      parent_category = create("marketplace_category")
      subcategory = create("marketplace_category", parent_category: parent_category)
      other_category = create("marketplace_category")

      matching_listing = create(:marketplace_listing, categories: [parent_category, subcategory])
      non_matching_listing = create(:marketplace_listing, categories: [other_category])

      subcategory_listings = Marketplace::Listing.with_category(subcategory.slug)
      assert_same_elements subcategory_listings, [matching_listing]

      parent_category_listings = Marketplace::Listing.with_category(parent_category.slug)
      assert_same_elements parent_category_listings, [matching_listing]
    end

    test "matches_name_or_description" do
      listing1 = create(:marketplace_listing, name: "Lorem ipsum foo",
                                           short_description: "does not match",
                                           full_description: "does not match")
      listing2 = create(:marketplace_listing, name: "Awesome listing",
                                           short_description: "does not match",
                                           full_description: "Lorem ipsum bar")
      listing3 = create(:marketplace_listing, name: "Somehow a listing",
                                           short_description: "Lorem ipsum bar",
                                           full_description: "does not match")
      listing4 = create(:marketplace_listing, name: "Fantastic listing",
                                           short_description: "does not match",
                                           full_description: "Lorem bacon bits")
      listing5 = create(:marketplace_listing, name: "Funniest listing",
                                           short_description: "does not match",
                                           full_description: "does not match",
                                           extended_description: "Lorem ipsum foo")

      listings = Marketplace::Listing.matches_name_or_description("ipsum")

      assert_includes listings, listing1, "should match name"
      assert_includes listings, listing2, "should match full_description"
      assert_includes listings, listing3, "should match short_description"
      refute_includes listings, listing4,
        "should not match listing without query in name or description fields"
      refute_includes listings, listing5, "should not match extended_description"
    end

    test "installed_on_repo returns listings installed on a given repo" do
      repo = create(:repository)
      installed_oauth_listing = create(:marketplace_listing, :verified)
      uninstalled_oauth_listing = create(:marketplace_listing, :verified)
      installed_ghapp_listing = create(:marketplace_listing, :integration, :verified)
      uninstalled_ghapp_listing = create(:marketplace_listing, :integration, :verified)

      installed_oauth_listing.listable.authorizations.create(user: repo.owner, scopes: ["repo"])
      installed_ghapp_listing.listable.install_on(repo.owner, repositories: [repo], installer: repo.owner, entry_point: :test_case)

      listings = Marketplace::Listing.installed_on_repo(repo)

      assert_includes listings, installed_oauth_listing
      assert_includes listings, installed_ghapp_listing
      refute_includes listings, uninstalled_oauth_listing
      refute_includes listings, uninstalled_ghapp_listing
    end
  end

  test "generates a slug" do
    new_listing = build(:marketplace_listing)
    assert_nil new_listing.slug
    assert_predicate new_listing, :valid?, "validation should set the slug"
    refute_nil new_listing.slug
  end

  test "does not overwrite specified slug on create" do
    new_listing = build(:marketplace_listing, slug: "so-fun")
    assert new_listing.save, new_listing.errors.full_messages.join(", ")
    assert_equal "so-fun", new_listing.reload.slug
  end

  test "updates slug when name changes and listing is draft" do
    listing = create(:marketplace_listing, :draft)
    listing.name = "A Brand New Name"
    assert listing.save, listing.errors.full_messages.join(", ")
    assert_equal "a-brand-new-name", listing.reload.slug
  end

  test "does not update slug when name changes and listing is not draft" do
    listing = create(:marketplace_listing, :verified)
    listing.name = "A Brand New Name"
    assert listing.save, listing.errors.full_messages.join(", ")
    refute_equal "a-brand-new-name", listing.reload.slug
  end

  test "must have a listable" do
    integration = create(:integration)
    oauth_app   = create :oauth_application
    user = create :user
    org = create :organization

    listing = build(:marketplace_listing)

    listing.listable = integration
    assert_predicate listing, :valid?, "should be valid with an integration"

    listing.listable = oauth_app
    assert_predicate listing, :valid?, "should be valid with an oauth_application"

    listing.listable = user
    assert_predicate listing, :valid?, "should be valid with a user"

    listing.listable = org
    assert_predicate listing, :valid?, "should be valid with a org"

    listing.listable = nil
    refute_predicate listing, :valid?, "should require a listable"
    assert_predicate listing.errors[:base], :any?, "should have a validation error"
  end

  context "#adminable_by?" do
    test "true when user is integration owner admin" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)

      assert listing.adminable_by?(integration.owner.admin)
    end

    test "true when user is OAuth app user" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)

      assert listing.adminable_by?(app.user)
    end

    test "false when user is unrelated to integration owner" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)

      refute listing.adminable_by?(create(:user))
    end

    test "false when user is a regular member of integration owner" do
      integration = create(:integration)
      member = create(:user)
      integration.owner.add_member(member)

      listing = create(:marketplace_listing, listable: integration)
      refute listing.adminable_by?(member)
    end

    test "false when user is not OAuth app user" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)

      refute listing.adminable_by?(create(:user))
    end

    test "false when user is a biztools user not connected to listing" do
      user = create(:biztools_user)
      listing = create(:marketplace_listing)

      refute listing.adminable_by?(user)
    end

    test "false when user is a site admin not connected to listing" do
      user = create(:staff_admin_user)
      listing = create(:marketplace_listing)

      refute listing.adminable_by?(user)
    end
  end

  context "#verified_approval_requestable_by?" do
    test "false for OAuth app owner as user with paid plans" do
      listing = create(:marketplace_listing_ready_for_review)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)

      refute listing.verified_approval_requestable_by?(owner)
      refute listing.async_verified_approval_requestable_by?(owner).sync
    end

    test "false for OAuth app owner as org without publisher verification completed" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, listable: integration)

      owner = listing.owner.admin
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, organization: org, agreement: @integrator_agreement)

      refute listing.verified_approval_requestable_by?(owner)
      refute listing.async_verified_approval_requestable_by?(owner).sync
    end

    test "true for OAuth app owner as org with publisher verification completed" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration)

      owner = listing.owner.admin
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, organization: org, agreement: @integrator_agreement)

      assert listing.verified_approval_requestable_by?(owner)
      assert listing.async_verified_approval_requestable_by?(owner).sync
    end

    test "false for OAuth app owner without 2FA" do
      listing = create(:marketplace_listing_ready_for_review)
      owner = listing.owner
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)

      refute listing.verified_approval_requestable_by?(owner)
      refute listing.async_verified_approval_requestable_by?(owner).sync
    end

    test "false for spammy OAuth app owner", skip_enterprise: true do
      listing = create(:marketplace_listing_ready_for_review)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)
      owner.mark_as_spammy(reason: "Spamming")

      refute listing.verified_approval_requestable_by?(owner)
      refute listing.async_verified_approval_requestable_by?(owner).sync
    end

    test "false for OAuth app owner without agreement signature" do
      listing = create(:marketplace_listing_ready_for_review)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)

      refute listing.verified_approval_requestable_by?(owner)
      refute listing.async_verified_approval_requestable_by?(owner).sync
    end

    test "false for GitHub app owner for listing with published paid plans without publisher verification" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      refute listing.verified_approval_requestable_by?(admin)
      refute listing.async_verified_approval_requestable_by?(admin).sync
    end

    test "true for GitHub app owner for listing with published paid plans with publisher verification" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      assert listing.verified_approval_requestable_by?(admin)
      assert listing.async_verified_approval_requestable_by?(admin).sync
    end

    test "false for GitHub app owner without 2FA" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      refute listing.verified_approval_requestable_by?(admin)
      refute listing.async_verified_approval_requestable_by?(admin).sync
    end

    test "false for spammy GitHub app owner", skip_enterprise: true do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)
      admin.mark_as_spammy(reason: "Spamming")

      refute listing.verified_approval_requestable_by?(admin)
      refute listing.async_verified_approval_requestable_by?(admin).sync
    end

    test "false for GitHub app owner without agreement signature" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)

      refute listing.verified_approval_requestable_by?(admin)
      refute listing.async_verified_approval_requestable_by?(admin).sync
    end

    test "true for a Copilot app without verified owner if feature flag is disabled" do
      GitHub.flipper[:marketplace_updated_verified_creator].disable

      integration = create(:integration)
      copilot_app = create(:marketplace_listing, :draft, :copilot,
        :with_free_plan,
        :with_contact_info,
        :with_hero_card,
        :with_screenshots,
        :with_webhook,
        listable: integration,
      )
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      assert copilot_app.verified_approval_requestable_by?(admin)
      assert copilot_app.async_verified_approval_requestable_by?(admin).sync
    end

    test "false for a Copilot app without verified owner if feature flag is enabled" do
      GitHub.flipper[:marketplace_updated_verified_creator].enable

      integration = create(:integration)
      copilot_app = create(:marketplace_listing, :draft, :copilot,
        :with_free_plan,
        :with_contact_info,
        :with_hero_card,
        :with_screenshots,
        :with_webhook,
        listable: integration,
      )
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      refute copilot_app.verified_approval_requestable_by?(admin)
      refute copilot_app.async_verified_approval_requestable_by?(admin).sync
    end

    test "true for a Copilot app with verified owner if feature flag is enabled" do
      GitHub.flipper[:marketplace_updated_verified_creator].enable

      integration = create(:integration)
      copilot_app = create(:marketplace_listing, :draft, :copilot,
        :with_free_plan,
        :with_contact_info,
        :with_hero_card,
        :with_screenshots,
        :with_webhook,
        :verified_publisher,
        listable: integration,
      )
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      assert copilot_app.verified_approval_requestable_by?(admin)
      assert copilot_app.async_verified_approval_requestable_by?(admin).sync
    end

    test "false for a random user" do
      listing = create(:marketplace_listing)
      rando = create(:two_factor_credential_user)

      refute listing.verified_approval_requestable_by?(rando)
      refute listing.async_verified_approval_requestable_by?(rando).sync
    end
  end

  context "#unverified_approval_requestable_by?" do
    test "true for OAuth app owner" do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)

      assert listing.unverified_approval_requestable_by?(owner)
      assert listing.async_unverified_approval_requestable_by?(owner).sync
    end

    test "false for OAuth app owner without 2FA" do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      owner = listing.owner
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)

      refute listing.unverified_approval_requestable_by?(owner)
      refute listing.async_unverified_approval_requestable_by?(owner).sync
    end

    test "false for spammy OAuth app owner", skip_enterprise: true do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)
      owner.mark_as_spammy(reason: "Spamming")

      refute listing.unverified_approval_requestable_by?(owner)
      refute listing.async_unverified_approval_requestable_by?(owner).sync
    end

    test "false for OAuth app owner without agreement signature" do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)

      refute listing.unverified_approval_requestable_by?(owner)
      refute listing.async_unverified_approval_requestable_by?(owner).sync
    end

    test "false for OAuth app owner when listing has published paid plans" do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      create(:marketplace_listing_plan, :paid, :published, listing: listing)
      owner = listing.owner
      owner.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: owner, agreement: @integrator_agreement)

      refute listing.unverified_approval_requestable_by?(owner)
      refute listing.async_unverified_approval_requestable_by?(owner).sync
    end

    test "true for GitHub app owner" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_unverified_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      assert listing.unverified_approval_requestable_by?(admin)
      assert listing.async_unverified_approval_requestable_by?(admin).sync
    end

    test "false for GitHub app owner without 2FA" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_unverified_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      refute listing.unverified_approval_requestable_by?(admin)
      refute listing.async_unverified_approval_requestable_by?(admin).sync
    end

    test "false for spammy GitHub app owner", skip_enterprise: true do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_unverified_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)
      admin.mark_as_spammy(reason: "Spamming")

      refute listing.unverified_approval_requestable_by?(admin)
      refute listing.async_unverified_approval_requestable_by?(admin).sync
    end

    test "false for GitHub app owner without agreement signature" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_unverified_review, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)

      refute listing.unverified_approval_requestable_by?(admin)
      refute listing.async_unverified_approval_requestable_by?(admin).sync
    end

    test "false for GitHub app owner when listing has published paid plans" do
      integration = create(:integration)
      listing = create(:marketplace_listing_ready_for_unverified_review, listable: integration)
      create(:marketplace_listing_plan, :paid, :published, listing: listing)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      refute listing.unverified_approval_requestable_by?(admin)
      refute listing.async_unverified_approval_requestable_by?(admin).sync
    end

    test "true for a Copilot app without verified owner if feature flag is disabled" do
      GitHub.flipper[:marketplace_updated_verified_creator].disable

      integration = create(:integration)
      copilot_app = create(:marketplace_listing_ready_for_unverified_review, :copilot, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      assert copilot_app.unverified_approval_requestable_by?(admin)
      assert copilot_app.async_unverified_approval_requestable_by?(admin).sync
    end

    test "false for a Copilot app without verified owner if feature flag is enabled" do
      GitHub.flipper[:marketplace_updated_verified_creator].enable

      integration = create(:integration)
      copilot_app = create(:marketplace_listing_ready_for_unverified_review, :copilot, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      refute copilot_app.unverified_approval_requestable_by?(admin)
      refute copilot_app.async_unverified_approval_requestable_by?(admin).sync
    end

    test "true for a Copilot app with verified owner if feature flag is enabled" do
      GitHub.flipper[:marketplace_updated_verified_creator].enable

      integration = create(:integration)
      copilot_app = create(:marketplace_listing_ready_for_unverified_review, :copilot, :verified_publisher, listable: integration)
      owner_org = integration.owner
      admin = owner_org.admin
      admin.two_factor_credential = create(:two_factor_credential)
      create(:marketplace_agreement_signature, signatory: admin, organization: owner_org, agreement: @integrator_agreement)

      assert copilot_app.unverified_approval_requestable_by?(admin)
      assert copilot_app.async_unverified_approval_requestable_by?(admin).sync
    end

    test "false for a random user" do
      listing = create(:marketplace_listing_ready_for_unverified_review)
      rando = create(:two_factor_credential_user)

      refute listing.unverified_approval_requestable_by?(rando)
      refute listing.async_unverified_approval_requestable_by?(rando).sync
    end
  end

  context "#allowed_to_edit?" do
    test "true when user is integration owner admin" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      assert listing.allowed_to_edit?(integration.owner.admin)
    end

    test "true when user is OAuth app user" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      assert listing.allowed_to_edit?(app.user)
    end

    test "false when user is unrelated to integration owner" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      refute listing.allowed_to_edit?(create(:user))
    end

    test "false when user is a regular member of integration owner" do
      integration = create(:integration)
      member = create(:user)
      integration.owner.add_member(member)

      listing = create(:marketplace_listing, listable: integration)
      refute listing.allowed_to_edit?(member)
    end

    test "false when user is not OAuth app user" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      refute listing.allowed_to_edit?(create(:user))
    end

    test "false when listing is rejected" do
      listing = create(:marketplace_listing, :rejected)
      agreement = create(:marketplace_agreement)

      assert_predicate listing, :rejected?
      refute listing.can_sign_integrator_agreement?(listing.owner, agreement: agreement)
    end

    test "false when the listing is archived" do
      app = create :oauth_application
      listing = create(:marketplace_listing, :archived, listable: app)
      refute listing.allowed_to_edit?(app.user)
    end

    test "true when user is a site admin and listing is a draft" do
      user = create(:staff_admin_user)
      listing = create(:marketplace_listing, :draft)

      assert listing.allowed_to_edit?(user)
    end

    test "true when user is a site admin and listing has requested approval" do
      user = create(:staff_admin_user)
      listing = create(:marketplace_listing, :verification_pending_from_draft)

      assert listing.allowed_to_edit?(user)
    end

    test "true when user is a site admin and listing is verified" do
      user = create(:staff_admin_user)
      listing = create(:marketplace_listing, :verified)

      assert listing.allowed_to_edit?(user)
    end

    test "false when user is a site admin and listing is archived" do
      user = create(:staff_admin_user)
      listing = create(:marketplace_listing, :archived)

      refute listing.allowed_to_edit?(user)
    end

    if GitHub.billing_enabled?
      test "true when user is a biztools user and listing is verification_pending_from_draft" do
        user = create(:biztools_user)
        listing = create(:marketplace_listing, :verification_pending_from_draft)

        assert listing.allowed_to_edit?(user)
      end

      test "true when user is a biztools user and listing is a draft" do
        user = create(:biztools_user)
        listing = create(:marketplace_listing, :draft)

        assert listing.allowed_to_edit?(user)
      end

      test "false when user is a biztools user and listing is archived" do
        user = create(:biztools_user)
        listing = create(:marketplace_listing, :archived)

        refute listing.allowed_to_edit?(user)
      end

      test "true when user is a biztools user and listing is verified" do
        user = create(:biztools_user)
        listing = create(:marketplace_listing, :verified)

        assert listing.allowed_to_edit?(user)
      end
    end
  end

  context "#owned_by_github?" do
    test "returns true if owned by github org" do
      org = create(:github_organization)
      github_app = create(:integration, owner: org)
      listing = build(:marketplace_listing, listable: github_app)

      assert_predicate listing, :owned_by_github?
    end

    test "returns false if not owned by github org" do
      listing = build(:marketplace_listing)
      assert listing.owner

      refute_predicate listing, :owned_by_github?
    end
  end

  context "#visible_to?" do
    test "true when listing is verified" do
      listing = create(:marketplace_listing, :verified)

      assert listing.visible_to?(create(:user))
      assert listing.visible_to?(nil), "should be visible to anonymous user"
    end

    test "true when listing is unverified" do
      listing = create(:marketplace_listing, :unverified)

      assert listing.visible_to?(create(:user))
      assert listing.visible_to?(nil), "should be visible to anonymous user"
    end

    test "true when listing is verification_pending_from_unverified" do
      listing = create(:marketplace_listing, :verification_pending_from_unverified)

      assert listing.visible_to?(create(:user))
      assert listing.visible_to?(nil), "should be visible to anonymous user"
    end

    test "false when listing is archived and account has not purchased the listing" do
      listing = create(:marketplace_listing, :archived)

      refute listing.visible_to?(create(:user))
    end

    test "true when plan is published and account has an active subscription for the listing" do
      listing = create(:marketplace_listing, :verified)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      plan_subscription = create :billing_plan_subscription
      create(:billing_subscription_item,
        plan_subscription_id: plan_subscription.id,
        subscribable: plan,
      )
      listing.delist!
      user = build(:user)

      user.stubs(:has_active_subscription_item_for?) do
        assert listing.visible_to?(user)
      end
    end

    test "false when listing is rejected" do
      listing = create(:marketplace_listing, :rejected)

      refute listing.visible_to?(create(:user))
    end

    test "false when listing is draft" do
      listing = create(:marketplace_listing, :draft)

      refute listing.visible_to?(create(:user))
    end

    test "false when listing is verification_pending_from_draft" do
      listing = create(:marketplace_listing, :verification_pending_from_draft)

      refute listing.visible_to?(create(:user))
    end
  end

  context "featured scope" do
    test "includes featured listings" do
      featured_listing = create(:marketplace_listing, :verified_with_hero_card)
      featured_listing.update! featured_at: Time.zone.now - 5.days
      future_featured_listing = create(:marketplace_listing, :verified_with_hero_card)
      future_featured_listing.update! featured_at: Time.zone.now + 5.days

      assert_predicate featured_listing, :featured?
      assert_equal [featured_listing], Marketplace::Listing.featured
    end

    test "excludes listings featured in the future" do
      listing = create(:marketplace_listing, :verified_with_hero_card)
      listing.update! featured_at: Time.zone.now + 5.days

      refute_predicate listing, :featured?
      assert_empty Marketplace::Listing.featured
    end
  end

  context "drafts scope" do
    test "includes listing in draft state" do
      listing = create(:marketplace_listing)
      assert_predicate listing, :draft?
      assert_equal [listing], Marketplace::Listing.drafts
    end

    test "excludes listings not in draft state" do
      verified_listing = create(:marketplace_listing, state: :verified)
      assert_predicate verified_listing, :verified?

      app_req_listing = create(:marketplace_listing, state: :verification_pending_from_draft)
      assert_predicate app_req_listing, :verification_pending_from_draft?

      archived_listing = create(:marketplace_listing, state: :archived)
      assert_predicate archived_listing, :archived?

      rejected_listing = create(:marketplace_listing, state: :rejected)
      assert_predicate rejected_listing, :rejected?

      assert_empty Marketplace::Listing.drafts
    end
  end

  context "for_org scope" do
    test "includes listing for integration owned by given org" do
      org1 = create(:organization)
      org2 = create(:organization)

      integration1 = create(:integration, owner: org1)
      listing1 = create(:marketplace_listing, listable: integration1)

      integration2 = create(:integration, owner: org2)
      listing2 = create(:marketplace_listing, listable: integration2)

      results = Marketplace::Listing.for_org(org1)

      assert_includes results, listing1
      refute_includes results, listing2
    end

    test "includes listing for OAuth app owned by given org" do
      org1 = create(:organization)
      org2 = create(:organization)

      app1 = create(:oauth_application, user: org1)
      listing1 = create(:marketplace_listing, listable: app1)

      app2 = create(:oauth_application, user: org2)
      listing2 = create(:marketplace_listing, listable: app2)

      results = Marketplace::Listing.for_org(org1)

      assert_includes results, listing1
      refute_includes results, listing2
    end

    test "excludes listings for products owned by a user" do
      user = create(:user)
      org = create(:organization)

      integration = create(:integration, owner: user)
      app = create(:oauth_application, user: user)

      listing1 = create(:marketplace_listing, listable: app)
      listing2 = create(:marketplace_listing, listable: integration)

      results = Marketplace::Listing.for_org(org)

      refute_includes results, listing1
      refute_includes results, listing2
    end
  end

  context "editable_by scope" do
    test "includes listing for integration owned by user" do
      user = create(:user)
      integration = create(:integration, owner: user)
      listing = create(:marketplace_listing, listable: integration)

      assert_equal [listing], Marketplace::Listing.editable_by(user)
    end

    test "includes listing for OAuth app owned by user" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      assert_equal [listing], Marketplace::Listing.editable_by(user)
    end

    test "includes listing for integration owned by org user admins" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      assert_equal [listing], Marketplace::Listing.editable_by(org.admin)
    end

    test "includes listing for OAuth app owned by org user admins" do
      org = create(:organization)
      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      assert_equal [listing], Marketplace::Listing.editable_by(org.admin)
    end

    test "excludes listing for integration owned by someone else" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)

      refute_includes Marketplace::Listing.editable_by(create(:user)), listing
    end

    test "excludes listing for OAuth app owned by someone else" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)

      refute_includes Marketplace::Listing.editable_by(create(:user)), listing
    end

    test "excludes listing for integration owned by org user belongs to" do
      org = create(:organization)
      user = create(:user)
      org.add_member user

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      refute_includes Marketplace::Listing.editable_by(user), listing
    end

    test "excludes listing for OAuth app owned by org user belongs to" do
      org = create(:organization)
      user = create(:user)
      org.add_member user

      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      refute_includes Marketplace::Listing.editable_by(user), listing
    end
  end

  context "visible_to scope" do

    test "includes listing for integration owned by user" do
      user = create(:user)
      integration = create(:integration, owner: user)
      listing = create(:marketplace_listing, listable: integration)

      assert_equal [listing], Marketplace::Listing.visible_to(user)
      assert listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "includes listing for OAuth app owned by user" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      assert_equal [listing], Marketplace::Listing.visible_to(user)
      assert listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "includes listings for both OAuth app and integration owned by user" do
      user = create(:user)
      oauth_app = create(:oauth_application, user: user)
      integration = create(:integration, owner: user)
      oauth_listing = create(:marketplace_listing, listable: oauth_app)
      integration_listing = create(:marketplace_listing, listable: integration)

      assert_same_elements [oauth_listing, integration_listing], Marketplace::Listing.visible_to(user)
    end

    test "includes listing for integration owned by org user admins" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      assert_equal [listing], Marketplace::Listing.visible_to(org.admin)
      assert listing.visible_to?(org.admin), "#visible_to? should agree with scope"
    end

    test "includes listing for OAuth app owned by org user admins" do
      org = create(:organization)
      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      assert_equal [listing], Marketplace::Listing.visible_to(org.admin)
      assert listing.visible_to?(org.admin), "#visible_to? should agree with scope"
    end

    test "excludes draft listing for integration owned by someone else" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)
      user = create(:user)

      refute_includes Marketplace::Listing.visible_to(user), listing
      refute listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "excludes draft listing for OAuth app owned by someone else" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)
      user = create(:user)

      refute_includes Marketplace::Listing.visible_to(user), listing
      refute listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "excludes draft listing for integration owned by org user belongs to" do
      org = create(:organization)
      user = create(:user)
      org.add_member user

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)

      refute_includes Marketplace::Listing.visible_to(user), listing
      refute listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "excludes draft listing for OAuth app owned by org user belongs to" do
      org = create(:organization)
      user = create(:user)
      org.add_member user

      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      refute_includes Marketplace::Listing.visible_to(user), listing
      refute listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "includes verified listing for app owned by another user" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      other_listing = create(:marketplace_listing, :verified)

      assert_same_elements [listing, other_listing], Marketplace::Listing.visible_to(user)
      assert listing.visible_to?(user), "#visible_to? should agree with scope"
      assert other_listing.visible_to?(user), "#visible_to? should agree with scope"
    end

    test "includes verified listings for site admin" do
      staff      = create :staff_admin_user
      listing    = create(:marketplace_listing, :verified)
      draft = create(:marketplace_listing)

      assert_equal [listing], Marketplace::Listing.visible_to(staff)
      assert listing.visible_to?(staff), "#visible_to? should agree with scope"
    end

    test "includes verified listings for biztools_users" do
      biz        = create :biztools_user
      listing    = create(:marketplace_listing, :verified)
      draft = create(:marketplace_listing)

      assert_equal [listing], Marketplace::Listing.visible_to(biz)
      assert listing.visible_to?(biz), "#visible_to? should agree with scope"
    end

    test "includes verified listing for integration owned by another user" do
      user = create(:user)
      integration = create(:integration, owner: user)
      listing = create(:marketplace_listing, listable: integration)

      other_listing = create(:marketplace_listing, :verified)

      assert_same_elements [listing, other_listing], Marketplace::Listing.visible_to(user)
      assert listing.visible_to?(user), "#visible_to? should agree with scope"
      assert other_listing.visible_to?(user), "#visible_to? should agree with scope"
    end
  end

  context "#paid?" do
    test "true when it has a paid plan" do
      listing = create(:marketplace_listing)
      create(:marketplace_listing_plan, :published, listing: listing, monthly_price_in_cents: 100)

      assert_predicate listing, :paid?
    end

    test "false when it has no plans" do
      listing = create(:marketplace_listing)

      refute_predicate listing, :paid?
    end

    test "false when it has only free plans" do
      listing = create(:marketplace_listing)
      create(:marketplace_listing_plan, :published, listing: listing, monthly_price_in_cents: 0, yearly_price_in_cents: 0)

      refute_predicate listing, :paid?
    end
  end

  context "#paid_listing_plans" do
    test "returns paid listing plans" do
      listing = create(:marketplace_listing)
      paid_plan = create(:marketplace_listing_plan, listing: listing, monthly_price_in_cents: 10_000)
      create(:marketplace_listing_plan, listing: listing, monthly_price_in_cents: 0, yearly_price_in_cents: 0)

      assert_equal [paid_plan], listing.paid_listing_plans
    end
  end

  context "#integratable_description" do
    test "returns 'application' for an OAuth app listing" do
      app = create :oauth_application
      listing = create(:marketplace_listing, listable: app)

      assert_equal "application", listing.integratable_description
    end

    test "returns 'integration' for an integration listing" do
      integration = create(:integration)
      listing = create(:marketplace_listing, listable: integration)

      assert_equal "integration", listing.integratable_description
    end
  end

  context "#integrator_agreement_signature_for" do
    test "returns user's signature made for the listing when it exists" do
      user = create(:user)
      org = create(:organization, admin: user)
      app = create(:oauth_application, user: org)
      agreement = create(:marketplace_agreement)
      listing = create(:marketplace_listing, listable: app)
      signature = create(:marketplace_agreement_signature,
                         signatory: user, agreement: agreement, organization: org)

      assert_equal signature, listing.integrator_agreement_signature_for(user)
    end

    test "returns latest signature made for the listing when many exist" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      agreement = create(:marketplace_agreement)
      listing = create(:marketplace_listing, listable: app)
      signature1 = create(:marketplace_agreement_signature, signatory: user, agreement: agreement)
      signature2 = create(:marketplace_agreement_signature, signatory: user, agreement: agreement)

      assert_equal signature2, listing.integrator_agreement_signature_for(user)
    end

    test "returns nil when integrator agreement does not exist" do
      user = create(:user)
      org = create(:organization, admin: user)
      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      assert_nil listing.integrator_agreement_signature_for(user)
    end

    test "returns nil when org has not signed integrator agreement" do
      user = create(:user)

      agreement = create(:marketplace_agreement)
      create(:marketplace_agreement_signature, signatory: user, agreement: agreement)

      org = create(:organization, admin: user)
      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      assert_nil listing.integrator_agreement_signature_for(user)
    end

    test "returns agreement when owner is org and one admin of org has singed and another views but has not signed integrator agreement" do
      user = create(:user)
      user2 = create(:user)
      agreement = create(:marketplace_agreement)
      org = create(:organization, admin: user)
      org.add_admin(user2)
      app = create(:oauth_application, user: org)

      signature1 = create(:marketplace_agreement_signature, signatory: user, agreement: agreement, organization: org)

      listing = create(:marketplace_listing, listable: app)

      assert_equal  signature1, listing.integrator_agreement_signature_for(user2)
    end

    test "returns nil when user has only signed end-user agreement" do
      user = create(:user)

      create(:marketplace_agreement)
      end_user_agreement = create(:marketplace_agreement, :end_user)
      create(:marketplace_agreement_signature, signatory: user, agreement: end_user_agreement)

      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      assert_nil listing.integrator_agreement_signature_for(user)
    end
  end

  context "#has_signed_integrator_agreement?" do
    test "true when owner of integratable is a user and has signed integrator agreement" do
      user = create(:user)
      integration = create(:integration, owner: user)
      listing = create(:marketplace_listing, listable: integration)
      agreement = create(:marketplace_agreement)
      create(:marketplace_agreement_signature, signatory: user, agreement: agreement)

      assert listing.has_signed_integrator_agreement?(agreement: agreement)
    end

    test "true when owner of integratable is an org and has signed integrator agreement" do
      agreement = create(:marketplace_agreement)
      user = create(:user)
      org = create(:organization, admin: user)
      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)
      create(:marketplace_agreement_signature, signatory: user, agreement: agreement, organization: org)

      assert listing.has_signed_integrator_agreement?(agreement: agreement)
    end

    test "false when no integrator agreement exists" do
      user = create(:user)
      integration = create(:integration, owner: user)
      listing = create(:marketplace_listing, listable: integration)

      refute_predicate listing, :has_signed_integrator_agreement?
    end

    test "false when user owner of integratable has not signed integrator agreement" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)
      agreement = create(:marketplace_agreement)

      refute listing.has_signed_integrator_agreement?(agreement: agreement)
    end

    test "false when org owner of integratable has not signed integrator agreement" do
      user = create(:user)
      org = create(:organization, admin: user)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing, listable: integration)
      agreement = create(:marketplace_agreement)

      refute listing.has_signed_integrator_agreement?(agreement: agreement)
    end
  end

  context "#sign_agreement" do
    test "returns true when end-user agreement is signed successfully" do
      agreement = create(:marketplace_agreement, :end_user)
      user = create(:user)
      listing = create(:marketplace_listing)

      assert_predicate agreement, :end_user?
      assert_difference "agreement.signatures.count" do
        assert listing.sign_agreement(user, agreement: agreement)
      end
    end

    test "returns true when integrator agreement is signed successfully for a user" do
      agreement = create(:marketplace_agreement)
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      assert_predicate agreement, :integrator?
      assert_difference "agreement.signatures.count" do
        assert listing.sign_agreement(user, agreement: agreement)
      end
    end

    test "returns true when integrator agreement is signed successfully for an organization" do
      agreement = create(:marketplace_agreement)
      user = create(:user)
      org = create(:organization, admin: user)
      app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing, listable: app)

      assert_predicate agreement, :integrator?
      assert_difference "agreement.signatures.count" do
        assert listing.sign_agreement(user, agreement: agreement)
      end
      assert_equal org, agreement.signatures.last.organization
    end

    test "returns false when no agreement is given" do
      user = create(:user)
      app = create(:oauth_application, user: user)
      listing = create(:marketplace_listing, listable: app)

      assert_no_difference "Marketplace::AgreementSignature.count" do
        refute listing.sign_agreement(user, agreement: nil)
      end
    end

    test "returns false when agreement fails to be signed" do
      agreement = create(:marketplace_agreement)
      listing = create(:marketplace_listing)

      assert_no_difference "Marketplace::AgreementSignature.count" do
        refute listing.sign_agreement(nil, agreement: agreement)
      end
    end

    test "returns false for integrator agreement when given user is not admin of the listing" do
      agreement = create(:marketplace_agreement)
      listing = create(:marketplace_listing)

      assert_predicate agreement, :integrator?
      assert_no_difference "Marketplace::AgreementSignature.count" do
        refute listing.sign_agreement(create(:user), agreement: agreement)
      end
    end
  end

  context "#configuration_path" do
    test "returns integration installations settings path when integratable is an integration" do
      listing = create(:marketplace_listing, :integration)
      expected_path = UrlHelpers.settings_user_installations_path

      configuration_path = listing.configuration_path.to_s

      assert_equal expected_path, configuration_path
    end

    test "returns OAuth app settings path when integratable is an OAuth app" do
      listing = create(:marketplace_listing)
      expected_path = UrlHelpers.settings_user_applications_path

      configuration_path = listing.configuration_path.to_s

      assert_equal expected_path, configuration_path
    end
  end

  context "#support_url_is_email?" do
    test "true when support_url is an email address" do
      listing = create(:marketplace_listing, support_url: "test@example.com")

      assert_predicate listing, :support_url_is_email?
    end

    test "false when support_url is a URL" do
      listing = create(:marketplace_listing, support_url: "https://example.com/help-me")

      refute_predicate listing, :support_url_is_email?
    end
  end

  context "listing_plan association" do
    test "destroys listing along with associated plans when plans have no subscription items" do
      listing = create(:marketplace_listing, :verified)
      plan = create(:marketplace_listing_plan, :published, listing: listing)

      assert listing.destroy

      assert_nil Marketplace::ListingPlan.find_by(id: plan.id)
      assert_nil Marketplace::Listing.find_by(id: listing.id)
    end

    test "doesn't destroy listing when associated plans have subscription items" do
      listing = create(:marketplace_listing, :verified)
      plan = create(:marketplace_listing_plan, :published, listing: listing)
      create(:billing_subscription_item, subscribable: plan)

      refute listing.destroy
    end
  end

  context "listing insights" do
    test "updates for a specified day" do
      yesterday = Date.yesterday
      yesterday_timestamp ||= yesterday.strftime("%Y-%m-%d 12:00:00")

      listing = create(:marketplace_listing, :verified)
      free_plan = create(:marketplace_listing_plan, :free, listing: listing)
      paid_plan = create(:marketplace_listing_plan, listing: listing, monthly_price_in_cents: 42_00)

      transactions = []
      transactions << create(:transaction, :mp_purchased, current_subscribable: paid_plan)
      transactions << create(:transaction, :mp_purchased, current_subscribable: paid_plan)
      transactions << create(:transaction, :mp_cancelled, old_subscribable: paid_plan)
      transactions << create(:transaction, :mp_changed, old_subscribable: free_plan, current_subscribable: paid_plan)
      transactions << create(:transaction, :mp_changed, old_subscribable: paid_plan, current_subscribable: free_plan)
      Transaction.where(id: transactions.map(&:id)).update_all(timestamp: yesterday_timestamp)

      # For mrr_recurring
      line_items = [:settled, :settled, :submitted_for_settlement].map do |status|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: status, transaction_type: "recurring-charge"),
          subscribable: paid_plan,
          quantity: 1,
          amount_in_cents: paid_plan.monthly_price_in_cents,
        )
      end

      # For mrr_gained
      line_items += [:settled, :submitted_for_settlement].map do |status|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: status, transaction_type: "prorate-charge"),
          subscribable: paid_plan,
          quantity: 1,
          amount_in_cents: paid_plan.monthly_price_in_cents,
        )
      end

      # Make sure line items from other listings aren't included
      other_listing = create(:marketplace_listing, :verified)
      other_plan = create(:marketplace_listing_plan, listing: other_listing, monthly_price_in_cents: 4200)
      line_items += %w(prorate-charge recurring-charge).map do |transaction_type|
        create(:billing_transaction_line_item,
          billing_transaction: create(:billing_transaction, last_status: :settled, transaction_type: transaction_type),
          subscribable: other_plan,
          quantity: 1,
          amount_in_cents: other_plan.monthly_price_in_cents,
        )
      end

      Billing::BillingTransaction::LineItem.where(id: line_items.map(&:id)).update_all(created_at: yesterday_timestamp)

      listing.update_insights_for(yesterday)

      assert insights = listing.insights.find_by(recorded_on: yesterday)
      assert_equal 2, insights.new_purchases
      assert_equal 2, insights.new_seats
      assert_equal 1, insights.upgrades
      assert_equal 1, insights.upgraded_seats
      assert_equal 1, insights.downgrades
      assert_equal 1, insights.downgraded_seats
      assert_equal 1, insights.cancellations
      assert_equal 1, insights.cancelled_seats
      assert_equal paid_plan.monthly_price_in_cents * 2, insights.mrr_gained
      assert_equal paid_plan.monthly_price_in_cents * 2, insights.mrr_lost
      assert_equal paid_plan.monthly_price_in_cents * 2, insights.mrr_recurring
    end
  end

  def create_installable_listing(owner: @user, create_subscription: true, create_installation: true)
    listing = create(:marketplace_listing, :integration, state: :verified)
    listing_plan = create(:marketplace_listing_plan, :free, listing: listing)
    user_plan_subscription = create(:billing_plan_subscription, user: owner)
    create(:billing_subscription_item,
      plan_subscription: user_plan_subscription,
      subscribable: listing_plan,
      quantity: 1,
    ) if create_subscription
    repo = create(:repository, owner: owner)
    listing.listable.install_on(owner, repositories: [repo], installer: @user, entry_point: :test_case) if create_installation

    listing
  end

  context "quick_installable_for" do
    test "returns installed/subscribed github apps for users" do
      listing = create_installable_listing
      create(:marketplace_listing, :integration, state: :verified)

      assert_same_elements Marketplace::Listing.quick_installable_for(@user).keys, [listing]
    end

    test "returns installed/subscribed github apps for orgs" do
      org = create(:organization, admin: @user)
      listing = create_installable_listing(owner: org)
      create(:marketplace_listing, :integration, state: :verified)

      assert_same_elements Marketplace::Listing.quick_installable_for(org).keys, [listing]
    end

    test "does not include apps with no installation" do
      listing = create_installable_listing(create_installation: false)

      refute_includes Marketplace::Listing.quick_installable_for(@user), listing
    end

    test "does not include apps with no subscription" do
      listing = create_installable_listing(create_subscription: false)

      refute_includes Marketplace::Listing.quick_installable_for(@user), listing
    end

    test "does not include apps with an inactive subscription" do
      listing = create_installable_listing(create_subscription: false)
      @user.subscription_items.update_all(quantity: 0)

      refute_includes Marketplace::Listing.quick_installable_for(@user), listing
    end
  end

  context "verified_and_shuffled" do
    test "returns a limited, randomly ordered set of verified listings" do
      verified_listings = create_list(:marketplace_listing, 3, state: :verified)
      unverified_listing = create(:marketplace_listing)

      listings = Marketplace::Listing.verified_and_shuffled(limit: 2)

      refute_includes listings, unverified_listing
      assert_equal 2, listings.count
      assert_includes verified_listings, listings.first
      assert_includes verified_listings, listings.second
    end
  end

  context "#set_filter_categories!" do
    test "adds free trial category if listing has free trial plans" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))

      refute listing.categories.include?(@free_trial_category)

      create(:marketplace_listing_plan, :free_trial, :published, listing: listing)
      listing.set_filter_categories!

      assert listing.categories.reload.include?(@free_trial_category)
    end

    test "does not add free trial category if listing has no free trial plans" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))

      refute listing.categories.include?(@free_trial_category)

      create(:marketplace_listing_plan, :published, listing: listing)
      listing.set_filter_categories!

      refute listing.categories.include?(@free_trial_category)
    end

    test "removes free trial category if free trials removed" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))
      free_trial_plan = create(:marketplace_listing_plan, :free_trial, :published, listing: listing)
      listing.set_filter_categories!

      assert listing.categories.reload.include?(@free_trial_category)

      free_trial_plan.destroy
      listing.set_filter_categories!

      refute listing.categories.reload.include?(@free_trial_category)
    end

    test "adds free category if listing has free plans" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))

      refute listing.categories.include?(@free_category)

      create(:marketplace_listing_plan, :free, :published, listing: listing)
      listing.set_filter_categories!

      assert listing.categories.reload.include?(@free_category)
    end

    test "removes free category if listing has no free plans" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))
      listing.categories << @free_category

      refute_predicate listing, :published_free_plans?
      assert listing.categories.include?(@free_category)

      listing.set_filter_categories!

      refute listing.categories.reload.include?(@free_category)
    end

    test "adds paid category if listing has paid plans" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))

      refute listing.categories.include?(@paid_category)

      create(:marketplace_listing_plan, :paid, :published, listing: listing)
      listing.set_filter_categories!

      assert listing.categories.reload.include?(@paid_category)
    end

    test "removes paid category if listing has no paid plans" do
      listing = create(:marketplace_listing, categories: create_list(:marketplace_category, 2))
      listing.categories << @paid_category

      refute_predicate listing, :published_paid_plans?
      assert listing.categories.include?(@paid_category)

      listing.set_filter_categories!

      refute listing.categories.reload.include?(@paid_category)
    end
  end

  context "#default_plan" do
    test "returns a published free-trial plan if one is available" do
      listing = create(:marketplace_listing, :verified)
      other_plan = create(:marketplace_listing_plan, :published, has_free_trial: false, listing: listing)
      free_trial_plan = create(:marketplace_listing_plan, :published, has_free_trial: true, listing: listing)

      assert_equal free_trial_plan, listing.default_plan
    end

    test "returns a published non-free-trial plan if no free trial plan is available" do
      listing = create(:marketplace_listing, :verified)
      other_plan = create(:marketplace_listing_plan, :published, has_free_trial: false, listing: listing)
      retired_free_trial_plan = create(:marketplace_listing_plan, :retired, has_free_trial: true, listing: listing)

      assert_equal other_plan, listing.default_plan
    end
  end

  context "#ready_for_submission?" do
    test "returns false if all information is filled in with paid plans and owner is user" do
      listing = create(:marketplace_listing_ready_for_review)

      refute_predicate listing, :ready_for_submission?
      refute listing.async_ready_for_submission?.sync
    end

    test "returns true if all information is filled in with free plans and owner is user" do
      listing = create(:marketplace_listing_ready_for_unverified_review)

      assert listing.ready_for_unverified_submission?
    end

    test "returns true if all information is filled in with free plans and owner is org" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_unverified_review, listable: integration)

      assert listing.ready_for_unverified_submission?
    end

    test "returns false if all information is filled in with paid plans and owner is org without publisher verification completed" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, listable: integration)

      refute listing.ready_for_submission?
      refute listing.async_ready_for_submission?.sync
    end

    test "returns true if all information is filled in with paid plans and owner is org with publisher verification completed" do
      org = create(:organization)
      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration)

      assert listing.ready_for_submission?
      assert listing.async_ready_for_submission?.sync
    end

    test "returns false if contact info not complete" do
      listing = create(:marketplace_listing_ready_for_review, technical_email: nil)

      refute_predicate listing, :ready_for_submission?
      refute listing.async_ready_for_submission?.sync
    end

    test "returns false if description not complete" do
      listing = create(:marketplace_listing_ready_for_review, full_description: "")

      refute_predicate listing, :ready_for_submission?
      refute listing.async_ready_for_submission?.sync
    end

    test "returns false if webhook not setup" do
      listing = create(:marketplace_listing_ready_for_review, webhook: nil)

      refute_predicate listing, :ready_for_submission?
      refute listing.async_ready_for_submission?.sync
    end

    test "returns false if install count is not met with paid plans" do
      org = create(:organization)
      oauth_app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: oauth_app)
      GitHub.flipper[:marketplace_publisher_allowed_fewer_installations].disable(org)
      T.must(OauthAuthorization.where(application: listing.listable).first).destroy!

      refute_predicate listing, :ready_for_submission?
    end

    test "returns true if install count is met with paid plans" do
      org = create(:organization)
      oauth_app = create(:oauth_application, user: org)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: oauth_app)

      assert_predicate listing, :ready_for_submission?
    end
  end

  test "install limit is reduced to 0 if actor is enabled by marketplace_publisher_allowed_fewer_installations feature flag" do
    org = create(:organization)
    oauth_app = create(:oauth_application, user: org)
    listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: oauth_app)
    GitHub.flipper[:marketplace_publisher_allowed_fewer_installations].enable(org)

    assert_equal 0, listing.required_installations_for_verification
  end

  test "install limit is not reduced to 0 if actor is not enabled by marketplace_publisher_allowed_fewer_installations feature flag" do
    org = create(:organization)
    oauth_app = create(:oauth_application, user: org)
    listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: oauth_app)
    GitHub.flipper[:marketplace_publisher_allowed_fewer_installations].disable(org)

    refute_equal 0, listing.required_installations_for_verification
  end

  context "#naming_and_links_completed?" do
    test "returns true if all name and links info is filled in" do
      listing = build(:marketplace_listing)

      listing.name = "Best app"
      listing.short_description = "The greatest ever"
      listing.support_url = "https://github.com"
      listing.privacy_policy_url = "https://github.com"
      listing.installation_url = "https://github.com"

      assert_predicate listing, :naming_and_links_completed?
    end

    test "returns false if any name and links info is missing" do
      listing = build(:marketplace_listing)

      listing.short_description = ""
      listing.support_url = "https://github.com"
      listing.privacy_policy_url = ""
      listing.installation_url = "https://github.com"

      refute_predicate listing, :naming_and_links_completed?
    end

    test "returns true if listing for Integration is missing optional installation_url" do
      listing = build(:marketplace_listing, :integration)

      listing.name = "Best app"
      listing.short_description = "The greatest ever"
      listing.support_url = "https://github.com"
      listing.privacy_policy_url = "https://github.com"
      listing.installation_url = ""

      assert_predicate listing, :naming_and_links_completed?
    end

    test "returns false if listing for OauthApplication is missing required installation_url" do
      listing = build(:marketplace_listing)

      listing.name = "Best app"
      listing.short_description = "The greatest ever"
      listing.support_url = "https://github.com"
      listing.privacy_policy_url = "https://github.com"
      listing.installation_url = ""

      refute_predicate listing, :naming_and_links_completed?
    end
  end

  context "#contact_info_completed?" do
    test "returns true if all contact info is filled in" do
      listing = build(:marketplace_listing)

      listing.technical_email = Faker::Internet.email
      listing.marketing_email = Faker::Internet.email
      listing.finance_email = Faker::Internet.email
      listing.security_email = Faker::Internet.email

      assert_predicate listing, :contact_info_completed?
    end

    test "returns false if contact info not complete" do
      listing = build(:marketplace_listing)

      listing.technical_email = nil
      listing.marketing_email = nil
      listing.finance_email = nil
      listing.security_email = nil

      refute_predicate listing, :contact_info_completed?
    end

    test "returns false if security email is missing" do
      listing = build(:marketplace_listing)

      listing.technical_email = Faker::Internet.email
      listing.marketing_email = Faker::Internet.email
      listing.finance_email = Faker::Internet.email
      listing.security_email = nil

      refute_predicate listing, :contact_info_completed?
    end
  end

  context "#logo_and_feature_card_completed?" do
    test "returns true if all feature card fields are completed" do
      listing = create(:marketplace_listing)

      listing.hero_card_background_image = create(:marketplace_listing_image, listing: listing)
      listing.bgcolor = "FFFFFF"

      assert_predicate listing, :logo_and_feature_card_completed?
    end

    test "returns false if any feature card fields are missing" do
      listing = create(:marketplace_listing)

      listing.hero_card_background_image = nil
      listing.bgcolor = nil

      refute_predicate listing, :logo_and_feature_card_completed?
    end
  end

  context "#listing_details_completed?" do
    test "returns true all descriptions are filled in" do
      listing = build(:marketplace_listing)

      listing.full_description = "Full description"
      listing.extended_description = "Extended description"

      assert_predicate listing, :listing_details_completed?
    end

    test "returns false if descriptions not completed" do
      listing = build(:marketplace_listing)

      listing.full_description = ""
      listing.extended_description = "Extended description"

      refute_predicate listing, :listing_details_completed?
    end
  end

  context "#plans_and_pricing_completed?" do
    test "returns true if listing has a published plan" do
      listing = create(:marketplace_listing)

      listing.listing_plans = [build(:marketplace_listing_plan, :published)]

      assert_predicate listing, :plans_and_pricing_completed?
    end

    test "returns false if listing has no plans" do
      listing = create(:marketplace_listing)

      listing.listing_plans = []

      refute_predicate listing, :plans_and_pricing_completed?
    end

    test "returns false if listing has only draft plans" do
      listing = create(:marketplace_listing)

      listing.listing_plans = [build(:marketplace_listing_plan, :draft)]

      refute_predicate listing, :plans_and_pricing_completed?
    end

    test "returns false if listing has only retired plans" do
      listing = create(:marketplace_listing)

      listing.listing_plans = [build(:marketplace_listing_plan, :retired)]

      refute_predicate listing, :plans_and_pricing_completed?
    end
  end

  context "#product_screenshots_completed?" do
    test "returns true listing has at least 1 screenshot" do
      listing = create(:marketplace_listing)

      listing.screenshots = [create(:marketplace_listing_screenshot)]

      assert_predicate listing, :product_screenshots_completed?
    end

    test "returns false if missing screenshots" do
      listing = create(:marketplace_listing)

      listing.screenshots = []

      refute_predicate listing, :product_screenshots_completed?
    end
  end

  context "#webhook_completed?" do
    test "returns true if webhook is setup" do
      listing = create(:marketplace_listing)

      listing.webhook = create(:hook)

      assert_predicate listing, :webhook_completed?
      assert listing.async_webhook_completed?.sync
    end

    test "returns false if webhook not setup" do
      listing = create(:marketplace_listing)

      listing.webhook = nil

      refute_predicate listing, :webhook_completed?
      refute listing.async_webhook_completed?.sync
    end
  end

  context "#zuora_slug" do
    test "returns the slug on the listing" do
      listing = create(:marketplace_listing)

      assert_equal listing.slug, listing.zuora_slug
    end
  end

  context "#recommended apps" do
    test "returns true if apps is recommended app" do
      trending_listing  = create(:marketplace_listing, :verified, name: "Acme, inc")
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.set("marketplace/recommendations", [trending_listing].pluck(:id).to_json)
      # rubocop:enable GitHub/DoNotUseGlobalKv
      assert_equal true, trending_listing.async_is_recommended?.sync
    end
  end

  context "#financial onboarding" do
    test "creates issue and enquques FinancialOnboardingJob when an unverified app initiates financial onboarding" do
      @github = create(:organization, login: "github")
      @repo = create(:private_repository, name: "marketplace", owner: @github, from_example: :simple)
      integration = create(:integration)
      @user = create(:user, login: "Marketplace-Bot")

      commit = @repo.commits.create({ message: "Add templates", committer: @github }) do |files|
        files.add ".github/ISSUE_TEMPLATE/onboard-paid-app-pending-from-unverified.md", <<~MARKDOWN
        ---
        name: Template for Onboarding Pending Verification from Unverified Apps (Paid)"
        about: Tracking issue for onboarding Pending Verification from Unverified apps on GitHub Marketplace
        title: Onboarding Pending Verification from Unverified App (Paid) - [App Name]
        ---
        Application Name - [App Name]
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @user)

      issue_count = Issue.count
      expected_count = issue_count + 1

      IssueTemplates.new(@repo)

      listing = create(
        :marketplace_listing_ready_for_review,
        :verified_publisher,
        :unverified,
        listable: integration,
      )
      listing.request_verified_approval!

      new_issue = Issue.last
      new_issue_title = T.must(new_issue).title
      new_issue_body = T.must(new_issue).body

      refute_includes new_issue_title, "[App Name]"
      assert_includes new_issue_body, "Application Name - #{listing.name}"
      assert_enqueued_jobs 1, only: FinancialOnboardingJob, queue: :marketplace
    end

    test "creates issue and enquques FinancialOnboardingJob when a draft app applies for publishing with a paid plan" do
      @github = create(:organization, login: "github")
      @repo = create(:private_repository, name: "marketplace", owner: @github, from_example: :simple)
      integration = create(:integration)
      @user = create(:user, login: "Marketplace-Bot")

      commit = @repo.commits.create({ message: "Add templates", committer: @github }) do |files|
        files.add ".github/ISSUE_TEMPLATE/onboard-paid-app-pending-from-draft.md", <<~MARKDOWN
        ---
        name: Template for Onboarding Pending Verification from Draft Apps (Paid)
        about: Tracking issue for onboarding Pending Verification from Draft apps on GitHub Marketplace
        title: Onboarding Pending Verification from Draft App (Paid) - [App Name]
        ---
        Application Name - [App Name]
        MARKDOWN
      end

      @repo.refs["refs/heads/master"].update(commit, @user)

      issue_count = Issue.count
      expected_count = issue_count + 1

      IssueTemplates.new(@repo)

      listing = create(
        :marketplace_listing_ready_for_review,
        :verified_publisher,
        listable: integration,
      )
      listing.request_verified_approval!

      new_issue = Issue.last
      new_issue_title = T.must(new_issue).title
      new_issue_body = T.must(new_issue).body

      refute_includes new_issue_title, "[App Name]"
      assert_includes new_issue_body, "Application Name - #{listing.name}"
      assert_enqueued_jobs 1, only: FinancialOnboardingJob, queue: :marketplace
    end

    test "does not enqueue FinancialOnboardingJob if issue creation fails when when an unverified app initiates financial onboarding" do
      @github = create(:organization, login: "github")
      org = create(:organization)
      user = create(:user, login: "monalisa")

      integration = create(:integration, owner: org)
      listing = create(
        :marketplace_listing_ready_for_review,
        :verified_publisher,
        :unverified,
        listable: integration,
      )
      listing.request_verified_approval!
      assert_enqueued_jobs 0, only: FinancialOnboardingJob, queue: :marketplace
    end

    test "does not enqueue FinancialOnboardingJob if issue creation fails when a draft app applies for publishing with a paid plan" do
      @github = create(:organization, login: "github")
      org = create(:organization)
      user = create(:user, login: "monalisa")

      integration = create(:integration, owner: org)
      listing = create(:marketplace_listing_ready_for_review, :verified_publisher, listable: integration)
      listing.request_verified_approval!(@user)

      assert_enqueued_jobs 0, only: FinancialOnboardingJob, queue: :marketplace
    end
  end

  context "#og_image_url" do
    test "it returns expected enhanced opengraph image url with correct cache key", skip_enterprise: true do
      listing = create(:marketplace_listing, :integration, state: :verified)

      # calculate expected cache key from specific resource attributes
      cache_key = Digest::SHA256.hexdigest(
        [
          listing.cached_installation_count,
          listing.slug,
          listing.owner,
          listing.updated_at
        ].join(":")
      )

      # enhanced opengraph url with expected cache slug
      image_url = "http://localhost:7071/#{cache_key}#{listing.permalink(include_host: false)}"

      assert_equal image_url, listing.og_image_url
    end
  end

  context "#can_viewer_see?" do
    test "returns true if listing is publicly listed when user is not nil" do
      user = create(:user)
      listing = create(:marketplace_listing, :integration, state: :verified)
      assert listing.can_viewer_see?(user)
    end

    test "returns true if listing is publicly listed when user is nil" do
      listing = create(:marketplace_listing, :integration, state: :verified)
      assert listing.can_viewer_see?(nil)
    end

    test "returns false if listing is not publicly listed when user is nil" do
      listing = create(:marketplace_listing, :integration, state: :draft)
      refute listing.can_viewer_see?(nil)
    end

    test "returns true if user has purchased listing" do
      user = create(:user)
      listing = create(:marketplace_listing, :integration, state: :unverified_pending)
      user.stubs(:user_or_org_account_has_purchased_listing?).returns(true)
      assert listing.can_viewer_see?(user)
    end

    test "returns true if user can_admin_marketplace_listings" do
      user = create(:user)
      listing = create(:marketplace_listing, :integration, state: :unverified_pending)
      user.stubs(:can_admin_marketplace_listings?).returns(true)
      assert listing.can_viewer_see?(user)
    end

    test "returns true if listing is adminable_by current user" do
      user = create(:user, :staff)
      listing = create(:marketplace_listing, :integration, state: :unverified_pending)
      assert listing.can_viewer_see?(user)
    end
  end

  context "audit log events" do
    test "creates an event when delisted" do
      events = subscribe("marketplace_listing.delist")
      listing = create(:marketplace_listing, :verified)
      listing.delist!(@admin, "test audit log")

      assert event = events.pop, "no event was created"
      assert_equal "marketplace_listing.delist", event.name

      expected_payload = {
        marketplace_listing: listing.name,
        marketplace_listing_id: listing.id,
        actor: @admin.login,
        actor_id: @admin.id,
        state: :archived,
        user: listing.owner.login,
        user_id: listing.owner.id,
        primary_category: listing.categories.first.name,
        secondary_category: "none",
        oauth_application: listing.listable.name,
        oauth_application_id: listing.listable_id,
      }
      assert_equal expected_payload, event.payload
    end

    test "creates an audit when rejected" do
      events = subscribe("marketplace_listing.reject")
      listing = create(:marketplace_listing, :verification_pending_from_draft)
      listing.reject!(@admin, "test audit log")

      assert event = events.pop, "no event was created"
      assert_equal "marketplace_listing.reject", event.name

      expected_payload = {
        marketplace_listing: listing.name,
        marketplace_listing_id: listing.id,
        actor: @admin.login,
        actor_id: @admin.id,
        state: :rejected,
        user: listing.owner.login,
        user_id: listing.owner.id,
        primary_category: listing.categories.first.name,
        secondary_category: "none",
        oauth_application: listing.listable.name,
        oauth_application_id: listing.listable_id,
      }
      assert_equal expected_payload, event.payload
    end

    test "creates an event when redrafted" do
      events = subscribe("marketplace_listing.redraft")
      listing = create(:marketplace_listing, :verification_pending_from_draft)
      listing.redraft!(@admin, "test audit log")

      assert event = events.pop, "no event was created"
      assert_equal "marketplace_listing.redraft", event.name

      expected_payload = {
        marketplace_listing: listing.name,
        marketplace_listing_id: listing.id,
        actor: @admin.login,
        actor_id: @admin.id,
        state: :draft,
        user: listing.owner.login,
        user_id: listing.owner.id,
        primary_category: listing.categories.first.name,
        secondary_category: "none",
        oauth_application: listing.listable.name,
        oauth_application_id: listing.listable_id,
      }
      assert_equal expected_payload, event.payload
    end
  end
end
