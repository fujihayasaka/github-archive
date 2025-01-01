# typed: true
# frozen_string_literal: true

require "test_helper"

class SuccessorsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @inviter = create(:verified_user)
    @invitee = create(:verified_user)
    @successor_invite = create(:successor_invitation, :account, inviter: @inviter, invitee: @invitee)
  end

  context "#mark_deceased" do
    test "marks a user as deceased" do
      refute @user.deceased?

      @user.mark_deceased

      @user.reload
      assert @user.deceased?
    end

    test "will not mark a user as deceased twice" do
      assert @user.mark_deceased
      refute @user.mark_deceased
      assert_equal "Deceased has already been set for this user", @user.errors.full_messages.to_sentence
    end
  end

  unless GitHub.enterprise?
    context "successor invitations" do
      test "#account_successor_for? returns true for user who accepted account successor invite" do
        inviter = create(:verified_user)

        decliner = create(:verified_user)
        create(:successor_invitation, :account, inviter: inviter, invitee: decliner).decline
        refute decliner.account_successor_for?(inviter)

        successor = create(:verified_user)
        create(:successor_invitation, :account, inviter: inviter, invitee: successor).accept

        assert successor.account_successor_for?(inviter)
      end

      test "#succeedable_by? returns false for blocked and suspended users" do
        inviter = create(:verified_user)
        blocked = create(:verified_user)
        inviter.block(blocked)

        suspended = create(:verified_user)
        suspended.suspend("Very naughty")

        normal = create(:verified_user)

        refute inviter.succeedable_by?(blocked)
        refute inviter.succeedable_by?(suspended)
        assert inviter.succeedable_by?(normal)
      end
    end

    test "#get_successor_invitation returns the last record" do
      user = create(:verified_user)
      create(:successor_invitation, :account, inviter: user, declined_at: Time.now)
      last_invite = create(:successor_invitation, :account, inviter: user)

      assert_equal user.get_successor_invitation, last_invite
    end

    context "#has_successor" do
      test "#has_successor returns false if a user has no successor invitation" do
        @successor_invite.destroy
        refute @inviter.has_successor?
      end

      test "#has_successor returns true if a user has a successor" do
        @successor_invite.accept
        assert @inviter.has_successor?
      end

      test "#has_successor returns false if invite has not been actioned" do
        refute @inviter.has_successor?
      end
    end

    context "notifications for cascade-deleted successor invitations" do
      test "inviter is notified when their successor's account is deleted" do
        successor = create(:user)
        inviter = create(:user)
        inviter.emails.first.verify!
        invite = create(:successor_invitation, inviter: inviter, invitee: successor, target: inviter)
        invite.accept

        SuccessionMailer.expects(:account_successor_removed)
            .once.with(invite).returns(stub(deliver_later: nil))

        successor.destroy
      end

      test "does not send emails regarding declined, canceled, revoked, or pending invites" do
        successor = create(:user)
        inviter = create(:user)
        inviter.emails.first.verify!

        assert_difference "SuccessorInvitation.count", 4 do
          create(:successor_invitation, inviter: inviter, invitee: successor, target: inviter).decline
          create(:successor_invitation, inviter: inviter, invitee: successor, target: inviter).cancel
          revoked = create(:successor_invitation, inviter: inviter, invitee: successor, target: inviter)
          revoked.accept
          revoked.revoke
          create(:successor_invitation, inviter: inviter, invitee: successor, target: inviter)
        end

        assert_difference "SuccessorInvitation.count", -4 do
          SuccessionMailer.expects(:account_successor_removed).never
          successor.destroy
        end
      end

      # note: in the first iteration of Digital Wills, inviter and target are always one and the same.
      # It will be worthwhile to test cascading deletion behaviour when this 1:1 relationship becomes untrue,
      # e.g. when we implement repository succession.
      test "does not send emails to nowhere when the inviter/target's account is deleted" do
        successor = create(:user)
        inviter = create(:user)
        inviter.emails.first.verify!
        create(:successor_invitation, inviter: inviter, invitee: successor, target: inviter).accept

        assert_difference "SuccessorInvitation.count", -1 do
          SuccessionMailer.expects(:account_successor_removed).never
          inviter.destroy
        end
      end
    end
  end
end
