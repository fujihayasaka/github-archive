# typed: true
# frozen_string_literal: true
require "test_helper"

class StafftoolsSpammyRenameDeleteOverrideTest < GitHub::TestCase
  fixtures do
    @staffer     = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @spammer     = create(:user, login: "spammer", spammy: true)
    @org_admin   = create(:user, login: "org-admin")
    @org         = create(:organization, admin: @org_admin, spammy: true)
    @spammyorg   = create(:organization, admin: @spammer, spammy: true)
    @spammyorg2  = create(:organization, admin: @spammer, spammy: true)
    @spammyorg3  = create(:organization, admin: @spammer, spammy: true)
  end

  setup do
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  if GitHub.spamminess_check_enabled?
    test "can override spammy rename" do
      refute @spammer.rename!("bar")
      refute Stafftools::SpammyRenameDeleteOverride.overridden?(user: @spammer, toggle_type: :renaming)

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @spammer, toggle_type: :renaming)
      assert Stafftools::SpammyRenameDeleteOverride.overridden?(user: @spammer, toggle_type: :renaming)
      assert @spammer.rename!("bar")
    end

    test "can see if spammy toggle is overridden" do
      refute Stafftools::SpammyRenameDeleteOverride.overridden?(user: @spammer, toggle_type: :renaming)
      refute @spammer.spammy_renaming_overridden?

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @spammer, toggle_type: :renaming)
      assert Stafftools::SpammyRenameDeleteOverride.overridden?(user: @spammer, toggle_type: :renaming)
      assert @spammer.spammy_renaming_overridden?
    end

    test "instrument spammy rename override" do
      events = subscribe "stafftools_spammy_override.update"

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @spammer, toggle_type: :renaming)

      expected_payload = {
        user_id: @spammer.id,
        user: @spammer.login,
        toggle_type: :renaming,
        override_type: "enable override",
      }

      assert event = events.pop, "an event was expected"
      assert_equal "stafftools_spammy_override.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "invalid toggle_types are rejected" do
      refute Stafftools::SpammyRenameDeleteOverride.toggle_type_valid?(:foo)
    end

    test "can override spammy delete" do
      spammer = create(:user)
      spammer.mark_as_spammy

      assert spammer.spammy?
      refute spammer.permit_deletion?(spammer), "deletion was improperly permitted"

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: spammer, toggle_type: :deleting)
      assert spammer.spammy_deleting_overridden?
      assert spammer.permit_deletion?(spammer), "deletion is not permitted"
    end

    test "can toggle override" do
      refute @spammer.spammy_renaming_overridden?
      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @spammer, toggle_type: :renaming)
      assert @spammer.spammy_renaming_overridden?
      assert @spammer.rename!("bar")

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @spammer, toggle_type: :renaming)
      refute @spammer.spammy_renaming_overridden?
      refute @spammer.rename!("baz")
    end

    test "can override spammy org delete" do
      assert @org.spammy?
      refute @org.permit_deletion?(@org_admin), "deletion was improperly permitted"

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @org, toggle_type: :deleting)
      assert @org.spammy_deleting_overridden?
      assert @org.permit_deletion?(@org_admin), "deletion is not permitted"
    end

    test "can override deleting for all spammy orgs" do
      Stafftools::SpammyRenameDeleteOverride.toggle_override_for_owned_orgs(actor: @staffer, user: @spammer, toggle_type: :deleting)
      assert @spammer.spammy_orgs_deleting_overridden?

      spam_orgs = [@spammyorg, @spammyorg2, @spammyorg3]

      spam_orgs.each do |org|
        assert org.spammy_deleting_overridden?
        assert org.permit_deletion?(@spammer), "deletion is not permitted"
      end
    end

    test "deletion override for an org allows all owners to delete it" do
      other_admin = create(:user)
      @org.add_admin(other_admin)

      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @org, toggle_type: :deleting)
      assert @org.spammy_deleting_overridden?
      assert @org.permit_deletion?(@org_admin), "deletion is not permitted"
      assert @org.permit_deletion?(other_admin), "deletion is not permitted"
    end

    test "deletion override for a user's owned orgs allows all owners to delete it" do
      other_admin = create(:user)
      @org.add_admin(other_admin)

      Stafftools::SpammyRenameDeleteOverride.toggle_override_for_owned_orgs(actor: @staffer, user: @org_admin, toggle_type: :deleting)
      assert @org.spammy_deleting_overridden?
      assert @org.permit_deletion?(@org_admin), "deletion is not permitted"
      assert @org.permit_deletion?(other_admin), "deletion is not permitted"
    end

    test "renaming override for a user's owned orgs allows all owners to delete it" do
      other_admin = create(:user)
      @org.add_admin(other_admin)

      Stafftools::SpammyRenameDeleteOverride.toggle_override_for_owned_orgs(actor: @staffer, user: @org_admin, toggle_type: :renaming)
      assert @org.spammy_renaming_overridden?
      assert @org.rename!("foo", actor: @org_admin)
      assert @org.rename!("baz", actor: other_admin)
    end

    test "can override spammy org rename" do
      Stafftools::SpammyRenameDeleteOverride.toggle_override(actor: @staffer, user: @org, toggle_type: :renaming)
      assert @org.spammy_renaming_overridden?
      assert @org.rename!("baz")
    end

    test "can override all spammy orgs from a spammy user" do
      Stafftools::SpammyRenameDeleteOverride.toggle_override_for_owned_orgs(actor: @staffer, user: @spammer, toggle_type: :renaming)
      assert @spammyorg.spammy_renaming_overridden?
      assert @spammyorg2.spammy_renaming_overridden?
      assert @spammyorg3.spammy_renaming_overridden?
      assert @spammyorg.rename!("foo")
      assert @spammyorg2.rename!("baz")
      assert @spammyorg3.rename!("bat")

      assert @spammer.spammy_orgs_renaming_overridden?
    end
  end
end
