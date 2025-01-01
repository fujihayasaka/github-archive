# typed: true
# frozen_string_literal: true

require "test_helper"

class AttributionInvitationTest < GitHub::TestCase
  include ActionMailer::TestHelper

  fixtures do
    @organization_1 = create(:organization)
    @organization_2 = create(:organization)

    @mannequin_1 = create(:mannequin, owner: @organization_1)
    @mannequin_2 = create(:mannequin, owner: @organization_1)
    @mannequin_3 = create(:mannequin, owner: @organization_2)
    @mannequin_4 = create(:mannequin, owner: @organization_2)

    @user_1 = create(:user)
    @user_2 = create(:user)
    @user_3 = create(:user)
    @user_4 = create(:user)

    @invitation_1 = create(:attribution_invitation, owner: @organization_1, source: @mannequin_1, creator: @user_1)
    @invitation_2 = create(:attribution_invitation, owner: @organization_1, source: @mannequin_2, creator: @user_2)
    @invitation_3 = create(:attribution_invitation, owner: @organization_2, source: @mannequin_3, creator: @user_3)
    @invitation_4 = create(:attribution_invitation, owner: @organization_2, source: @mannequin_4, creator: @user_4)

    @invitation_ids = [@invitation_1, @invitation_2, @invitation_3, @invitation_4].map(&:id)
  end

  test "has a valid factory" do
    assert_valid @invitation_1
  end

  test "references a Mannequin as AttributionInvitation#source" do
    assert @invitation_1.source.mannequin?
  end

  test "references a User as AttributionInvitation#target" do
    assert @invitation_1.target.user?
  end

  test "references a User as AttributionInvitation#creator" do
    assert @invitation_1.creator.user?
  end

  test "references an Organization as AttributionInvitation#owner" do
    assert @invitation_1.owner.organization?
  end

  context "state transitions" do
    context "from invited" do
      test "can be accepted" do
        invited_attribution_invitation = create(:attribution_invitation)
        invited_attribution_invitation.accept!
        assert invited_attribution_invitation.accepted?
      end

      test "can be rejected" do
        invited_attribution_invitation = create(:attribution_invitation)
        invited_attribution_invitation.reject!
        assert invited_attribution_invitation.rejected?
      end

      test "can be canceled" do
        invited_attribution_invitation = create(:attribution_invitation)
        invited_attribution_invitation.cancel!
        assert invited_attribution_invitation.canceled?
      end

      test "cannot be completed" do
        invited_attribution_invitation = create(:attribution_invitation)
        assert_raises Workflow::NoTransitionAllowed do
          invited_attribution_invitation.complete!
        end
      end
    end

    context "from accepted" do
      test "can be completed" do
        accepted_attribution_invitation = create(:attribution_invitation,
                                                 state: :accepted)
        accepted_attribution_invitation.complete!

        assert accepted_attribution_invitation.completed?
      end

      test "cannot be canceled" do
        accepted_attribution_invitation = create(:attribution_invitation,
                                                 state: :accepted)
        assert_raises Workflow::NoTransitionAllowed do
          accepted_attribution_invitation.cancel!
        end
      end
    end

    context "from completed" do
      test "cannot be accepted" do
        completed_attribution_invitation = create(:attribution_invitation,
                                                  state: :completed)
        assert_raises Workflow::NoTransitionAllowed do
          completed_attribution_invitation.accept!
        end
      end

      test "cannot be canceled" do
        completed_attribution_invitation = create(:attribution_invitation,
                                                  state: :completed)
        assert_raises Workflow::NoTransitionAllowed do
          completed_attribution_invitation.cancel!
        end
      end
    end

    context "from canceled" do
      test "cannot be accepted" do
        canceled_attribution_invitation = create(:attribution_invitation,
                                                  state: :canceled)
        assert_raises Workflow::NoTransitionAllowed do
          canceled_attribution_invitation.accept!
        end
      end

      test "cannot be completed" do
        canceled_attribution_invitation = create(:attribution_invitation,
                                                  state: :canceled)
        assert_raises Workflow::NoTransitionAllowed do
          canceled_attribution_invitation.complete!
        end
      end
    end
  end

  test "#accept enqueues a RewriteMannequinAssociationsJob" do
    invitation = create(:attribution_invitation)

    assert_enqueued_with(job: RewriteMannequinAssociationsJob, args: [
      invitation.source,
      invitation.target,
      invitation,
    ]) do
      invitation.accept!
    end
  end

  test "#display_state returns formatted string of state" do
    assert_equal @invitation_1.display_state, "Invited"
  end

  context "send_invitation_email callback" do
    test "is called when bypass_email is false" do
      assert_enqueued_emails 2 do
        invitation = create(:attribution_invitation, bypass_email: false)
      end
    end

    test "is not called when bypass_email is true" do
      assert_enqueued_emails 1 do
        invitation = create(:attribution_invitation, bypass_email: true)
      end
    end
  end

  context "#present_mannequins_and_users" do
    test "returns all records when all source mannequins and target users are present" do
      @organization_1.add_member(@user_1)
      @organization_1.add_member(@user_2)
      @organization_2.add_member(@user_3)
      @organization_2.add_member(@user_4)

      invitation_ids = AttributionInvitation.where(id: @invitation_ids).present_mannequins_and_users.ids
      expected_invitation_ids = [@invitation_1, @invitation_2, @invitation_3, @invitation_4].map(&:id)

      assert_equal(invitation_ids, expected_invitation_ids)
    end

    test "returns present records when a mannequin is missing" do
      @organization_1.add_member(@user_1)
      @organization_1.add_member(@user_2)
      @organization_2.add_member(@user_3)
      @organization_2.add_member(@user_4)

      @mannequin_4.destroy

      invitation_ids = AttributionInvitation.where(id: @invitation_ids).present_mannequins_and_users.ids
      expected_invitation_ids = [@invitation_1, @invitation_2, @invitation_3].map(&:id)

      assert_equal(invitation_ids, expected_invitation_ids)
    end

    test "returns present records when a user is missing" do
      @organization_1.add_member(@user_1)
      @organization_1.add_member(@user_2)
      @organization_2.add_member(@user_3)
      @organization_2.add_member(@user_4)

      @user_4.destroy

      invitation_ids = AttributionInvitation.where(id: @invitation_ids).present_mannequins_and_users.ids
      expected_invitation_ids = [@invitation_1, @invitation_2, @invitation_3].map(&:id)

      assert_equal(invitation_ids, expected_invitation_ids)
    end

    test "returns present records when a user is not a member of the organization" do
      @organization_1.add_member(@user_1)
      @organization_1.add_member(@user_2)
      @organization_2.add_member(@user_3)

      invitation_ids = AttributionInvitation.where(id: @invitation_ids).present_mannequins_and_users.ids
      expected_invitation_ids = [@invitation_1, @invitation_2, @invitation_3].map(&:id)

      assert_equal(invitation_ids, expected_invitation_ids)
    end
  end
end
