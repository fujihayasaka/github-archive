# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipMatchBanTest < GitHub::TestCase
  fixtures do
    @match_ban = create(:sponsorship_match_ban)
    @staff = create(:staff_admin_user)
  end

  context "#sponsor_login" do
    test "returns the login of the sponsor" do
      sponsor = build(:user)
      match_ban = build(:sponsorship_match_ban, sponsor: sponsor)
      assert_equal sponsor.login, match_ban.sponsor_login
    end
  end

  context ".ban" do
    test "creates a match ban" do
      assert_difference -> { SponsorshipMatchBan.count }, 1 do
        result = SponsorshipMatchBan.create_for(
          sponsorable: create(:user),
          sponsor: create(:user),
          actor: @staff,
        )

        assert_predicate result, :success?
        assert_empty result.errors
      end
    end

    test "requires a sponsorable" do
      assert_no_difference -> { SponsorshipMatchBan.count } do
        result = SponsorshipMatchBan.create_for(
          sponsorable: nil,
          sponsor: create(:user),
          actor: @staff,
        )

        refute_predicate result, :success?
        assert_equal ["Sponsorable is required"], result.errors
      end
    end

    test "requires a sponsor" do
      assert_no_difference -> { SponsorshipMatchBan.count } do
        result = SponsorshipMatchBan.create_for(
          sponsorable: create(:user),
          sponsor: nil,
          actor: @staff,
        )

        refute_predicate result, :success?
        assert_equal ["Sponsor is required"], result.errors
      end
    end

    test "requires an actor" do
      assert_no_difference -> { SponsorshipMatchBan.count } do
        result = @match_ban.unban(actor: nil)

        refute_predicate result, :success?
        assert_equal ["Actor is required"], result.errors
      end
    end

    test "instruments creation event" do
      events = subscribe "sponsorship_match_ban.create"
      sponsorable = create(:user)
      sponsor = create(:user)

      result = SponsorshipMatchBan.create_for(
        sponsorable: sponsorable,
        sponsor: sponsor,
        actor: @staff,
      )

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge({
        sponsorship_match_ban_id: T.must(SponsorshipMatchBan.last).id,
        user: sponsorable.login,
        user_id: sponsorable.id,
        sponsor: sponsor.login,
        sponsor_id: sponsor.id,
      })
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#unban" do
    test "destroys a match ban" do
      assert_difference -> { SponsorshipMatchBan.count }, -1 do
        result = @match_ban.unban(actor: @staff)

        assert_predicate result, :success?
        assert_empty result.errors
      end
    end

    test "requires an actor" do
      assert_no_difference -> { SponsorshipMatchBan.count } do
        result = @match_ban.unban(actor: nil)

        refute_predicate result, :success?
        assert_equal ["Actor is required"], result.errors
      end
    end

    test "instruments creation event" do
      events = subscribe "sponsorship_match_ban.destroy"

      result = @match_ban.unban(actor: @staff)

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(@staff).merge({
        sponsorship_match_ban_id: @match_ban.id,
        user: @match_ban.sponsorable.login,
        user_id: @match_ban.sponsorable.id,
        sponsor: @match_ban.sponsor.login,
        sponsor_id: @match_ban.sponsor.id,
      })
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end
