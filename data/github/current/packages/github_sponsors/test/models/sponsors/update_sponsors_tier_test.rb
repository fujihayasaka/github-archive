# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsUpdateSponsorsTierTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, :sponsorable)
    @listing = @user.sponsors_listing
  end

  context "sponsors listing tier update" do
    test "sponsorable updates a draft tier" do
      tier = create(:sponsors_tier, sponsors_listing: @listing)
      amount = 5
      new_monthly_price = amount * 100
      new_yearly_price = new_monthly_price * 12

      Sponsors::UpdateSponsorsTier.call(
        tier: tier,
        description: "A new description",
        amount: 5,
        viewer: @user,
        welcome_message: "Welcome new sponsor!",
      )

      assert_equal "$5 a month", tier.reload.name
      assert_equal "A new description", tier.description
      assert_equal "Welcome new sponsor!", tier.welcome_message
      assert_equal new_monthly_price, tier.monthly_price_in_cents
      assert_equal new_yearly_price, tier.yearly_price_in_cents
      assert_nil tier.repository
    end

    test "sets the repository for a draft tier that previously did not have a repository" do
      org = create(:organization, :sponsorable, admin: @user)
      listing = org.sponsors_listing
      tier = listing.default_tier
      refute_predicate tier, :has_repository?
      repo = create(:private_repository, owner: org)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(repository_id: repo.id.to_s))
      end

      assert_equal repo, tier.repository
    end

    test "changes the repository for a published tier and revokes access to the old repository" do
      tier = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      old_repo = tier.repository

      sponsorship1 = create(:sponsorship, tier: tier, sponsorable: @user)
      sponsorship_repo1 = create(:sponsorship_repository, sponsors_tier: tier, sponsor: sponsorship1.sponsor,
        sponsorable: @user, repository: old_repo)

      sponsorship2 = create(:sponsorship, tier: tier, sponsorable: @user)
      sponsorship_repo2 = create(:sponsorship_repository, sponsors_tier: tier, sponsor: sponsorship2.sponsor,
        sponsorable: @user, repository: old_repo)

      new_repo = create(:private_repository, :org_owned)
      new_repo.add_member(@user, action: :admin)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [sponsorship1.sponsor_id, old_repo.id, tier.id],
      ) do
        assert_enqueued_with(
          job: RevokeSponsorsOnlyRepositoryAccessJob,
          args: [sponsorship2.sponsor_id, old_repo.id, tier.id],
        ) do
          Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(repository_id: new_repo.id.to_s))
        end
      end

      assert_equal new_repo, tier.reload.repository
    end

    test "revokes access to repository when removing repository from a tier that has sponsors" do
      tier = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      old_repo = tier.repository

      sponsorship1 = create(:sponsorship, tier: tier, sponsorable: @user)
      sponsorship_repo1 = create(:sponsorship_repository, sponsors_tier: tier, sponsor: sponsorship1.sponsor,
        sponsorable: @user, repository: old_repo)

      sponsorship2 = create(:sponsorship, tier: tier, sponsorable: @user)
      sponsorship_repo2 = create(:sponsorship_repository, sponsors_tier: tier, sponsor: sponsorship2.sponsor,
        sponsorable: @user, repository: old_repo)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [sponsorship1.sponsor_id, old_repo.id, tier.id],
      ) do
        assert_enqueued_with(
          job: RevokeSponsorsOnlyRepositoryAccessJob,
          args: [sponsorship2.sponsor_id, old_repo.id, tier.id],
        ) do
          Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(repository_id: nil))
        end
      end

      refute_predicate tier.reload, :has_repository?
    end

    test "does not imply one-time tier is recurring in the name" do
      tier = create(:sponsors_tier, :one_time, sponsors_listing: @listing)

      Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(amount: 4))

      tier = tier.reload
      assert_match /one time/, tier.name
      assert_equal 4_00, tier.monthly_price_in_cents
      assert_equal 4_00, tier.yearly_price_in_cents
    end

    test "creates an audit log event for a description update for published tier for approved listing" do
      tier = @listing.sponsors_tiers.first
      expected_payload = base_event_payload_for(tier).merge(
        previous_description: tier.description,
        description: "A new description",
        user: @user.login,
        user_id: @user.id,
      )
      events = subscribe "sponsors.sponsored_developer_tier_description_update"

      Sponsors::UpdateSponsorsTier.call(
        inputs_for(tier).merge(description: "A new description")
      )

      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload
    end

    test "creates a Hydro and audit log events when the tier welcome message changes" do
      tier = @listing.default_tier
      tier.update!(welcome_message: "hello sponsor!")

      events = subscribe "sponsors.update_tier_welcome_message"
      expected_payload = base_event_payload_for(tier).merge(
        welcome_message: "hello updated sponsor!",
        user: @user.login,
        user_id: @user.id,
      )

      Sponsors::UpdateSponsorsTier.call(
        inputs_for(tier).merge(welcome_message: "hello updated sponsor!")
      )

      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.UpdateTierWelcomeMessage")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        sponsorable: Hydro::EntitySerializer.user(@user),
        total_active_sponsors: 0,
        actor: Hydro::EntitySerializer.user(@user),
      }, schema: "github.sponsors.v1.UpdateTierWelcomeMessage")
    end

    test "creates a Hydro and audit log events when the tier welcome message changes for orgs" do
      travel_to "2023-11-13"
      listing = create(:sponsors_listing, :approved, :for_org)
      sponsorable = listing.sponsorable
      tier = listing.sponsors_tiers.first
      tier.update!(welcome_message: "hello sponsor!")

      events = subscribe "sponsors.update_tier_welcome_message"
      expected_payload = base_event_payload_for(tier).merge(
        welcome_message: "hello updated sponsor!",
        org: sponsorable.login,
        org_id: sponsorable.id,
        actor: sponsorable.admin.login,
        actor_id: sponsorable.admin.id
      )

      Sponsors::UpdateSponsorsTier.call(
        inputs_for(tier).merge(
          welcome_message: "hello updated sponsor!", viewer: sponsorable.admin
        )
      )

      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.UpdateTierWelcomeMessage")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        sponsorable: Hydro::EntitySerializer.user(listing.sponsorable),
        total_active_sponsors: 0,
        actor: Hydro::EntitySerializer.user(sponsorable.admin),
      }, schema: "github.sponsors.v1.UpdateTierWelcomeMessage")
    end

    test "does not create a Hydro nor audit log event when the tier welcome message stays the same" do
      tier = @listing.default_tier
      tier.update!(welcome_message: "hello sponsor!")

      events = subscribe "sponsors.update_tier_welcome_message"

      Sponsors::UpdateSponsorsTier.call(inputs_for(tier))

      assert_nil events.pop
      refute_hydro_messages(schema: "github.sponsors.v1.UpdateTierWelcomeMessage")
    end

    test "does not create an event when the tier welcome message is the same with leading or trailing spaces" do
      tier = @listing.default_tier
      tier.update!(welcome_message: "hello sponsor!")

      events = subscribe "sponsors.update_tier_welcome_message"

      Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(welcome_message: "  #{tier.welcome_message}"))

      assert_nil events.pop
      refute_hydro_messages(schema: "github.sponsors.v1.UpdateTierWelcomeMessage")
    end

    test "creates a Hydro and audit log events when the sponsors-only repo is changed" do
      travel_to "2023-11-13"
      tier = @listing.default_tier
      old_repo = create(:private_repository, :org_owned)
      new_repo = create(:private_repository, owner: old_repo.owner)
      old_repo.add_member(@user, action: :admin)
      new_repo.add_member(@user, action: :admin)
      tier.update!(repository: old_repo)

      events = subscribe "sponsors.update_tier_repository"
      expected_payload = base_event_payload_for(tier).merge(
        user: @user.login,
        user_id: @user.id,
      ).merge(new_repo.event_context).merge(old_repo.event_context(prefix: :old_repo))

      Sponsors::UpdateSponsorsTier.call(
        inputs_for(tier).merge(repository_id: new_repo.id)
      )

      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.UpdateTierRepository")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        old_repository: Hydro::EntitySerializer.repository(old_repo),
        repository: Hydro::EntitySerializer.repository(new_repo),
        sponsorable: Hydro::EntitySerializer.user(@user),
        total_active_sponsors: 0,
        actor: Hydro::EntitySerializer.user(@user),
        repository_owner: Hydro::EntitySerializer.user(new_repo.owner),
        old_repository_owner: Hydro::EntitySerializer.user(old_repo.owner),
      }, schema: "github.sponsors.v1.UpdateTierRepository")
    end

    test "creates a Hydro and audit log events when the sponsors-only repo is added" do
      travel_to "2023-11-13"
      tier = @listing.default_tier
      assert_nil tier.repository_id
      new_repo = create(:private_repository, :org_owned)
      new_repo.add_member(@user, action: :admin)

      events = subscribe "sponsors.update_tier_repository"
      expected_payload = base_event_payload_for(tier).merge(
        repo: new_repo,
        user: @user.login,
        user_id: @user.id,
      ).merge(new_repo.event_context)

      Sponsors::UpdateSponsorsTier.call(
        inputs_for(tier).merge(repository_id: new_repo.id)
      )

      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.UpdateTierRepository")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        listing: Hydro::EntitySerializer.sponsors_listing(@listing),
        old_repository: nil,
        repository: Hydro::EntitySerializer.repository(new_repo),
        sponsorable: Hydro::EntitySerializer.user(@user),
        total_active_sponsors: 0,
        actor: Hydro::EntitySerializer.user(@user),
        repository_owner: Hydro::EntitySerializer.user(new_repo.owner),
        old_repository_owner: nil,
      }, schema: "github.sponsors.v1.UpdateTierRepository")
    end

    test "creates a Hydro and audit log events when the sponsors-only repo is added for orgs" do
      travel_to "2023-11-14"
      listing = create(:sponsors_listing, :approved, :for_org)
      sponsorable = listing.sponsorable
      tier = listing.sponsors_tiers.first
      new_repo = create(:private_repository, owner: sponsorable)

      events = subscribe "sponsors.update_tier_repository"
      expected_payload = base_event_payload_for(tier).merge(
        repo: new_repo,
        org: sponsorable.login,
        org_id: sponsorable.id,
        actor: sponsorable.admin.login,
        actor_id: sponsorable.admin.id
      ).merge(new_repo.event_context)

      Sponsors::UpdateSponsorsTier.call(
        inputs_for(tier).merge(repository_id: new_repo.id, viewer: sponsorable.admin)
      )

      refute_nil event = events.pop, "should have had an event"
      assert_equal expected_payload, event.payload

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.UpdateTierRepository")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        tier: Hydro::EntitySerializer.sponsors_tier(tier),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        old_repository: nil,
        repository: Hydro::EntitySerializer.repository(new_repo),
        sponsorable: Hydro::EntitySerializer.user(sponsorable),
        total_active_sponsors: 0,
        actor: Hydro::EntitySerializer.user(sponsorable.admin),
        repository_owner: Hydro::EntitySerializer.user(new_repo.owner),
        old_repository_owner: nil,
      }, schema: "github.sponsors.v1.UpdateTierRepository")
    end

    test "does not create a Hydro nor audit log event when the sponsors-only repo does not change" do
      tier = @listing.default_tier
      tier.update!(welcome_message: "hello sponsor!")

      events = subscribe "sponsors.update_tier_repository"

      Sponsors::UpdateSponsorsTier.call(inputs_for(tier))

      assert_nil events.pop
      refute_hydro_messages(schema: "github.sponsors.v1.UpdateTierRepository")
    end

    test "enqueues a job to invite sponsors to repository if a repository is added" do
      org = create(:organization, :sponsorable, admin: @user)
      tier = @listing.default_tier
      repository = create(:private_repository, owner: org)
      sponsorship = create(:sponsorship, sponsorable: @user, tier: tier)
      sponsor = sponsorship.sponsor

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        assert_enqueued_with(
          job: GrantSponsorsOnlyRepositoryAccessJob,
          args: [sponsor.id, repository.id, tier.id]
        ) do
          Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(repository_id: repository.id.to_s))
        end
      end
      assert_equal repository.id, tier.reload.repository_id
    end

    # See: https://github.com/github/sponsors/issues/3313
    test "does not enqueue a revoke access job if the repository id is not changed" do
      tier = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      sponsorship = create(:sponsorship, sponsorable: @user, tier: tier)
      # Must have a SponsorshipRepository record or there would be nothing to revoke, meaning this test would always pass.
      create(:sponsorship_repository, sponsorable: @user, sponsors_tier: tier, repository: tier.repository, sponsor: sponsorship.sponsor)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(repository_id: tier.repository_id.to_s))
      end
    end

    # See: https://github.com/github/sponsors/issues/3313
    #
    # The repository_id param is an empty string (not `nil`) when no repository is selected
    test "does not enqueue a revoke access job if the repository id param is an empty string and the tier's repository_id is nil" do
      tier = create(:sponsors_tier, :published, repository_id: nil, sponsors_listing: @listing)
      sponsorship = create(:sponsorship, sponsorable: @user, tier: tier)
      # Must have a SponsorshipRepository record or there would be nothing to revoke, meaning this test would always pass.
      create(:sponsorship_repository, sponsorable: @user, sponsors_tier: tier, sponsor: sponsorship.sponsor)

      assert_no_enqueued_jobs(only: RevokeSponsorsOnlyRepositoryAccessJob) do
        Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(repository_id: ""))
      end
    end

    test "enqueues a job to invite sponsors to new repo and revoke access from old repo if a repository is changed" do
      tier = create(:sponsors_tier, :published, :with_repository, sponsors_listing: @listing)
      old_repo = tier.repository
      org = create(:organization, :sponsorable, admin: @user)
      repository = create(:private_repository, owner: org)
      sponsorship = create(:sponsorship, sponsorable: @user, tier: tier)
      create(:sponsorship_repository, sponsorable: @user, sponsors_tier: tier, repository: old_repo, sponsor: sponsorship.sponsor)
      sponsor = sponsorship.sponsor
      new_repository = create(:private_repository, owner: org)

      assert_enqueued_with(
        job: RevokeSponsorsOnlyRepositoryAccessJob,
        args: [sponsor.id, tier.repository_id, tier.id]
      ) do
        assert_enqueued_with(
          job: GrantSponsorsOnlyRepositoryAccessJob,
          args: [sponsor.id, new_repository.id, tier.id]
        ) do
          Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(
            tier: tier,
            repository_id: new_repository.id.to_s,
          ))
        end
      end
      assert_equal new_repository.id, tier.reload.repository_id
    end

    test "ignores inviting existing sponsors when a repository is not added" do
      org = create(:organization, :sponsorable, admin: @user)
      tier = @listing.sponsors_tiers.first
      sponsorship = create(:sponsorship, sponsorable: @user, tier: tier)
      sponsor = sponsorship.sponsor

      assert_no_enqueued_jobs only: GrantSponsorsOnlyRepositoryAccessJob do
        Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(description: "new description"))
      end
      assert_equal "new description", tier.reload.description
    end

    test "raises error when non-sponsorable attempts to update tier" do
      listing = create(:sponsors_listing)
      tier = create(:sponsors_tier, sponsors_listing: listing, name: "$5 a month")
      other_user = create(:user)

      error = assert_raises Sponsors::UpdateSponsorsTier::ForbiddenError do
        Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(viewer: other_user))
      end
      assert_equal "#{other_user.login} does not have permission to change the Sponsors tier.", error.message
    end

    test "raises error when tier does not update" do
      tier = create(:sponsors_tier, sponsors_listing: @listing, name: "$5 a month")

      error = assert_raises Sponsors::UpdateSponsorsTier::UnprocessableError do
        Sponsors::UpdateSponsorsTier.call(inputs_for(tier).merge(amount: 0))
      end
      assert_equal "Could not update Sponsors tier: Monthly price must be greater than 0, " \
        "Annual price must be greater than 0", error.message
    end
  end

  private

  def base_event_payload_for(tier)
    payload = {
      description: tier.description,
      welcome_message: tier.welcome_message,
      actor: @user.login,
      actor_id: @user.id,
      sponsors_listing: tier.sponsors_listing.slug,
      sponsors_listing_id: tier.sponsors_listing.id,
      sponsors_tier: tier.name,
      sponsors_tier_id: tier.id,
      monthly_price_in_cents: tier.monthly_price_in_cents,
      yearly_price_in_cents: tier.yearly_price_in_cents,
      state: :published,
    }
    if tier.repository
      payload[:repo] = tier.repository.name_with_owner
      payload[:repo_id] = tier.repository_id
    end
    payload
  end

  def inputs_for(tier)
    {
      tier: tier,
      description: tier.description,
      amount: tier.monthly_price_in_cents / 100,
      viewer: @user,
      welcome_message: tier.welcome_message,
    }
  end
end unless GitHub.enterprise?
