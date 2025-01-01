# typed: true
# frozen_string_literal: true

require "test_helper"

class PotentialSponsorshipTest < GitHub::TestCase
  fixtures do
    @bot = create(:bot)
    @spammer = create(:spammy_user)
    @user = create(:user)
  end

  context "#human_state" do
    test "returns human-readable description of each state" do
      assert_equal "Pending", PotentialSponsorship.new.human_state
      assert_equal "Acknowledged", PotentialSponsorship.new(state: :acknowledged).human_state
      assert_equal "Signed up for Sponsors", PotentialSponsorship.new(state: :sponsors_listing_created).human_state
      assert_equal "Sponsorship created", PotentialSponsorship.new(state: :sponsorship_created).human_state
      assert_equal "Pending", PotentialSponsorship.new(state: :some_invalid_state).human_state
    end
  end

  context "state transitions" do
    test "transitions from pending to acknowledged" do
      potential_sponsorship = create(:potential_sponsorship, :pending)
      potential_sponsorship.acknowledge!
      assert_predicate potential_sponsorship.reload, :acknowledged?
    end

    test "transitions from pending to sponsors_listing_created" do
      potential_sponsorship = create(:potential_sponsorship, :pending)
      potential_sponsorship.mark_as_sponsors_listing_created!
      assert_predicate potential_sponsorship.reload, :sponsors_listing_created?
    end

    test "transitions from acknowledged to sponsors_listing_created" do
      potential_sponsorship = create(:potential_sponsorship, :acknowledged)
      potential_sponsorship.mark_as_sponsors_listing_created!
      assert_predicate potential_sponsorship.reload, :sponsors_listing_created?
    end

    test "transitions from sponsors_listing_created to sponsorship_created" do
      potential_sponsorship = create(:potential_sponsorship, :sponsors_listing_created)
      potential_sponsorship.mark_as_sponsorship_created!
      assert_predicate potential_sponsorship.reload, :sponsorship_created?
    end
  end

  context "validations" do
    test "requires a potential sponsor" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsor: nil)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsor], "must exist"
    end

    test "requires a potential sponsorable" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: nil)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "must exist"
    end

    test "requires a non-bot potential sponsorable" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: @bot)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "must be a user or an organization"
    end

    test "requires a non-bot potential sponsor" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsor: @bot)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsor], "must be a user or an organization"
    end

    test "requires a non-spammy potential sponsorable" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: @spammer)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "cannot be spammy"
    end if GitHub.spamminess_check_enabled?

    test "requires a non-spammy potential sponsor" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsor: @spammer)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsor], "cannot be spammy"
    end if GitHub.spamminess_check_enabled?

    test "requires a creator" do
      potential_sponsorship = PotentialSponsorship.new(created_by: nil)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:created_by], "must exist"
    end

    test "requires a unique potential sponsor-potential sponsorable pair" do
      potential_sponsorship1 = create(:potential_sponsorship)
      potential_sponsorship2 = PotentialSponsorship.new(potential_sponsor: potential_sponsorship1.potential_sponsor,
        potential_sponsorable: potential_sponsorship1.potential_sponsorable)
      refute_predicate potential_sponsorship2, :valid?
      assert_includes potential_sponsorship2.errors[:potential_sponsorable_id], "has already been taken"
    end

    test "disallows potential sponsorable to have an approved Sponsors listing on create" do
      potential_sponsorable = create(:user, :sponsorable)
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "already has a public Sponsors profile"
    end

    test "disallows potential sponsorable to have a waitlisted Sponsors listing on create" do
      potential_sponsorable = create(:sponsors_listing, :waitlisted).sponsorable
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable],
        "has signed up for Sponsors and is waiting on a response from GitHub"
    end

    test "disallows potential sponsorable to have a pending-approval Sponsors listing on create" do
      potential_sponsorable = create(:sponsors_listing, :pending_approval).sponsorable
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable],
        "has signed up for Sponsors and is waiting on a response from GitHub"
    end

    test "allows potential sponsorable to have a draft Sponsors listing on create" do
      potential_sponsorable = create(:sponsors_listing, :draft).sponsorable
      potential_sponsorship = build(:potential_sponsorship, potential_sponsorable: potential_sponsorable)
      assert_predicate potential_sponsorship, :valid?
    end

    test "disallows potential sponsorable to have a banned Sponsors listing on create" do
      potential_sponsorable = create(:sponsors_listing, :banned).sponsorable
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "had their Sponsors profile taken down"
    end

    test "disallows potential sponsorable to have a spammy Sponsors listing on create" do
      potential_sponsorable = create(:sponsors_listing, :spammy).sponsorable
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "had their Sponsors profile taken down"
    end

    test "disallows potential sponsorable to have an SDN-disabled Sponsors listing on create" do
      potential_sponsorable = create(:sponsors_listing, :sdn_disabled).sponsorable
      potential_sponsorship = PotentialSponsorship.new(potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsorable], "had their Sponsors profile taken down"
    end

    test "allows sponsorable to have a Sponsors listing on update" do
      potential_sponsorship = create(:potential_sponsorship)
      create(:sponsors_listing, sponsorable: potential_sponsorship.potential_sponsorable)
      potential_sponsorship.message = "some message"
      assert_predicate potential_sponsorship, :valid?
    end

    test "disallows sponsor and sponsorable to be the same" do
      potential_sponsorship = PotentialSponsorship.new(potential_sponsor: @user, potential_sponsorable: @user)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:potential_sponsor], "can't be the same as potential sponsorable"
    end

    test "disallows actor and sponsorable to be the same" do
      potential_sponsorship = PotentialSponsorship.new(created_by: @user, potential_sponsorable: @user)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:created_by], "can't be the same as potential sponsorable"
    end

    test "disallows creator who is blocked by potential sponsorable" do
      creator = create(:user)
      @user.block(creator)
      potential_sponsorship = PotentialSponsorship.new(created_by: creator, potential_sponsorable: @user)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:base],
        "Cannot nudge #{@user} to create a GitHub Sponsors profile at this time."
    end

    test "disallows sponsor who is blocked by potential sponsorable" do
      potential_sponsorable = create(:user)
      potential_sponsorable.block(@user)
      potential_sponsorship = PotentialSponsorship.new(potential_sponsor: @user,
        potential_sponsorable: potential_sponsorable)
      refute_predicate potential_sponsorship, :valid?
      assert_includes potential_sponsorship.errors[:base],
        "Cannot nudge #{potential_sponsorable} to create a GitHub Sponsors profile at this time."
    end

    if GitHub.email_verification_enabled?
      test "requires the creator to have a verified email address on create" do
        potential_sponsorship = PotentialSponsorship.new(created_by: @user)
        refute_predicate potential_sponsorship, :valid?
        assert_includes potential_sponsorship.errors[:created_by], "must have a verified email address"
      end
    else
      test "does not require the creator to have a verified email address on create" do
        potential_sponsorship = build(:potential_sponsorship, created_by: @user)
        assert_predicate potential_sponsorship, :valid?
      end
    end

    test "does not require the creator to have a verified email address on update" do
      creator = create(:user, :verified)
      potential_sponsorship = create(:potential_sponsorship, created_by: creator)
      creator.emails.each(&:unverify!)
      potential_sponsorship.message = "some message"
      assert_predicate potential_sponsorship, :valid?
    end
  end

  context "banner notice" do
    test "resets banner for potential sponsorable on create when state=pending" do
      potential_sponsorship = create(:potential_sponsorship)
      potential_sponsorable = potential_sponsorship.potential_sponsorable
      refute potential_sponsorable.dismissed_notice?(PotentialSponsorship::NOTICE),
        "should have reset the notice when creating a potential sponsorship"

      potential_sponsorable.dismiss_notice(PotentialSponsorship::NOTICE)
      assert potential_sponsorable.dismissed_notice?(PotentialSponsorship::NOTICE)

      create(:potential_sponsorship, potential_sponsorable: potential_sponsorable)
      refute potential_sponsorable.dismissed_notice?(PotentialSponsorship::NOTICE),
        "should have reset the notice after creating a different potential sponsorship"
    end

    test "does not reset banner for potential sponsorable on update" do
      potential_sponsorship = create(:potential_sponsorship)
      potential_sponsorable = potential_sponsorship.potential_sponsorable

      potential_sponsorable.dismiss_notice(PotentialSponsorship::NOTICE)
      assert potential_sponsorable.dismissed_notice?(PotentialSponsorship::NOTICE)

      potential_sponsorship.message = "some message"
      potential_sponsorship.save!

      assert potential_sponsorable.dismissed_notice?(PotentialSponsorship::NOTICE),
        "should not have reset the notice after updating"
    end

    test "resets banner for org potential sponsorable's admins on create when state=pending" do
      org_admin1, org_admin2 = create_pair(:user)
      org = create(:organization, admin: org_admin1)
      org.add_admin(org_admin2)
      assert_same_elements [org_admin1, org_admin2], org.reload.admins

      org_admin1.dismiss_notice(PotentialSponsorship::NOTICE)
      org_admin2.dismiss_notice(PotentialSponsorship::NOTICE)
      assert org_admin1.dismissed_notice?(PotentialSponsorship::NOTICE)
      assert org_admin2.dismissed_notice?(PotentialSponsorship::NOTICE)

      create(:potential_sponsorship, potential_sponsorable: org)
      refute org_admin1.dismissed_notice?(PotentialSponsorship::NOTICE),
        "should have reset the notice after creating a potential sponsorship"
      refute org_admin2.dismissed_notice?(PotentialSponsorship::NOTICE),
        "should have reset the notice after creating a potential sponsorship"
    end

    test "does not reset banner on create when state is not pending" do
      user = create(:user)
      user.dismiss_notice(PotentialSponsorship::NOTICE)
      assert user.dismissed_notice?(PotentialSponsorship::NOTICE)

      potential_sponsorship = create(:potential_sponsorship, :acknowledged, potential_sponsorable: user)
      assert user.dismissed_notice?(PotentialSponsorship::NOTICE),
        "should not have reset the notice after creating a non-pending potential sponsorship"
    end
  end
end
