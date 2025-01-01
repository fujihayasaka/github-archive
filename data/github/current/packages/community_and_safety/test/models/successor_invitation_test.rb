# typed: true
# frozen_string_literal: true

require "test_helper"

class SuccessorInvitationTest < GitHub::TestCase
  fixtures do
    @inviter = create(:verified_user)
    @invitee = create(:user)
    @stranger = create(:user)
  end

  unless GitHub.enterprise?
    context "validations" do
      test "inviter cannot be nil" do
        invite = SuccessorInvitation.new(inviter: nil, invitee: @invitee, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:inviter], "can't be blank"
      end

      test "invitee cannot be nil" do
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: nil, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:invitee], "can't be blank"
      end

      test "target cannot be nil" do
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: nil)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:target], "can't be blank"
      end

      test "inviter and invitee cannot be the same user" do
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @inviter, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:base], "inviter and invitee cannot be the same user"
      end

      test "inviter cannot be blocking invitee" do
        @inviter.block(@invitee)
        assert @inviter.blocking?(@invitee)

        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:base], "that user cannot be appointed as a successor at this time"
      end

      test "invitee cannot be blocking inviter" do
        @invitee.block(@inviter)
        assert @invitee.blocking?(@inviter)

        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:base], "that user cannot be appointed as a successor at this time"
      end

      test "inviter cannot be spammy" do
        @inviter.mark_as_spammy

        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:base], "user is spammy"
      end

      test "inviter must have a verified email" do
        @inviter.primary_user_email.unverify!
        refute @inviter.primary_user_email.verified?

        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:base], "inviter does not have a verified email"
      end

      test "invitee cannot be an org" do
        org = create(:organization)
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: org, target: @inviter)

        refute_predicate invite, :valid?
        assert invite.errors.full_messages.include? "invitee must be a user"
      end

      test "invitee cannot be a bot" do
        bot = create(:bot)
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: bot, target: @inviter)

        refute_predicate invite, :valid?
        assert invite.errors.full_messages.include? "invitee must be a user"
      end
    end

    context "actor permissions" do
      test "only the invitee may accept" do
        stranger = create(:user)
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.accept(actor: stranger)
        end
        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.accept(actor: @inviter)
        end
        assert invite.accept(actor: @invitee)
      end

      test "only the invitee may decline" do
        stranger = create(:user)
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.decline(actor: stranger)
        end
        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.decline(actor: @inviter)
        end
        assert invite.decline(actor: @invitee)
      end

      test "only the inviter may cancel" do
        stranger = create(:user)
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.cancel(actor: stranger)
        end
        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.cancel(actor: @invitee)
        end
        assert invite.cancel(actor: @inviter)
      end

      test "only the inviter may revoke" do
        stranger = create(:user)
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter, accepted_at: Time.now)

        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.revoke(actor: stranger)
        end
        assert_raises SuccessorInvitation::ActorPermissionError do
          invite.revoke(actor: @invitee)
        end

        assert invite.revoke
      end
    end

    context "mailer actions connected to state changes" do
      test "upon acceptance, the inviter is notified that their successor was confirmed" do
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

        SuccessionMailer.expects(:account_successor_accepted).once.with(invite).returns(stub(deliver_later: nil))

        invite.accept
      end

      test "upon decline, the inviter is notified that their successor has declined" do
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

        SuccessionMailer.expects(:account_successor_declined).once.with(invite).returns(stub(deliver_later: nil))

        invite.decline
      end

      test "upon revoking, the inviter is notified that their successor was removed" do
        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter, accepted_at: Time.now)

        SuccessionMailer.expects(:account_successor_removed).once.with(invite).returns(stub(deliver_later: nil))

        invite.revoke
      end
    end

    context "invitation states and transitions" do
      context "a pending invitation" do
        test "can be accepted" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.accept

          assert invite.accepted?
        end

        test "can be declined" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.decline

          assert_predicate invite, :declined?
        end

        test "can be cancelled" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.cancel

          assert invite.canceled?
        end
      end

      context "an already-accepted invitation" do
        test "cannot be accepted twice" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.accept
          assert invite.accepted?

          assert_raises SuccessorInvitation::AlreadyAcceptedError do
            invite.accept
          end
        end

        test "cannot be declined" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.accept
          assert invite.accepted?

          assert_raises SuccessorInvitation::AlreadyAcceptedError do
            invite.decline
          end
        end

        test "cannot be canceled" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.accept
          assert invite.accepted?

          assert_raises SuccessorInvitation::AlreadyAcceptedError do
            invite.cancel
          end
        end
      end

      context "an already-declined invitation" do
        test "cannot be declined again" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.decline
          assert invite.declined?

          assert_raises SuccessorInvitation::AlreadyDeclinedError do
            invite.decline
          end
        end

        test "cannot be accepted" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.decline
          assert invite.declined?

          assert_raises SuccessorInvitation::AlreadyDeclinedError do
            invite.accept
          end
        end

        test "cannot be canceled" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.decline
          assert invite.declined?

          assert_raises SuccessorInvitation::AlreadyDeclinedError do
            invite.cancel
          end
        end
      end

      context "an already-canceled invitation" do
        test "cannot be canceled again" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.cancel
          assert invite.canceled?

          assert_raises SuccessorInvitation::AlreadyCanceledError do
            invite.cancel
          end
        end

        test "cannot be accepted" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.cancel
          assert invite.canceled?

          assert_raises SuccessorInvitation::AlreadyCanceledError do
            invite.accept
          end
        end

        test "cannot be declined" do
          invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
          invite.cancel
          assert invite.canceled?

          assert_raises SuccessorInvitation::AlreadyCanceledError do
            invite.decline
          end
        end
      end

      context "revocation" do
        test "only an accepted invitation can be revoked" do
          declined_invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter, declined_at: Time.now)
          canceled_invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter, canceled_at: Time.now)
          pending_invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

          assert_raises SuccessorInvitation::AlreadyDeclinedError do
            declined_invite.revoke
          end
          assert_raises SuccessorInvitation::AlreadyCanceledError do
            canceled_invite.revoke
          end
          assert_raises SuccessorInvitation::InvitePendingError do
            pending_invite.revoke
          end

          accepted_invite = (pending_invite.accept; pending_invite)
          assert accepted_invite.revoke
        end
      end
    end

    context "scopes" do
      test "#pending returns only invitations in pending state" do
        pending = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
        accepted = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, accepted_at: Time.now)
        canceled = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, canceled_at: Time.now)
        declined = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, declined_at: Time.now)

        assert_same_elements SuccessorInvitation.all, [pending, accepted, canceled, declined]
        assert_same_elements SuccessorInvitation.pending, [pending]
      end

      test "#declined returns only invitations in declined state" do
        pending = SuccessorInvitation.create(inviter: create(:verified_user), invitee: @invitee, target: @inviter)
        accepted = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, accepted_at: Time.now)
        canceled = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, canceled_at: Time.now)
        declined = SuccessorInvitation.create(inviter: @inviter, invitee: create(:user), target: @inviter, declined_at: Time.now)

        assert_same_elements SuccessorInvitation.all, [pending, accepted, canceled, declined]
        assert_same_elements SuccessorInvitation.declined, [declined]
      end

      test "#accepted returns only invitations in accepted state" do
        pending = SuccessorInvitation.create(inviter: create(:verified_user), invitee: @invitee, target: @inviter)
        accepted = SuccessorInvitation.create(inviter: @inviter, invitee: create(:user), target: @inviter, accepted_at: Time.now)
        canceled = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, canceled_at: Time.now)
        declined = SuccessorInvitation.create(inviter: create(:verified_user), invitee: create(:user), target: @inviter, declined_at: Time.now)

        assert_same_elements SuccessorInvitation.all, [pending, accepted, canceled, declined]
        assert_same_elements SuccessorInvitation.accepted, [accepted]
      end
    end

    context "post-create mailers" do
      test "queues up an account succession invitation email to the invitee" do
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)

        SuccessionMailer.expects(:account_successor_invite)
            .once.with(invite).returns(stub(deliver_later: nil))

        invite.save!
      end

      test "queues up a notification email to the inviter" do
        invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)

        SuccessionMailer.expects(:account_successor_added)
            .once.with(invite).returns(stub(deliver_later: nil))

        invite.save!
      end
    end

    context "#terminate_all" do
      context "for just one user" do
        test "cancels pending invitations sent by that user" do
          user = create(:user, :verified)
          successor = create(:user)
          invitation = create(:successor_invitation, inviter: user, invitee: successor, target: user)

          SuccessorInvitation.terminate_all(user)

          invitation.reload
          assert invitation.canceled?
        end

        test "declines pending invitations sent by others" do
          user = create(:user, :verified)
          successor = create(:user)
          invitation = create(:successor_invitation, inviter: user, invitee: successor, target: user)

          SuccessorInvitation.terminate_all(successor)

          invitation.reload
          assert invitation.declined?
        end

        test "revokes invitations that the user has accepted" do
          sender = create(:user, :verified)
          user = create(:user)
          invitation = create(:successor_invitation, inviter: sender, invitee: user, target: sender, accepted_at: Time.now)

          SuccessorInvitation.terminate_all(user)

          invitation.reload
          assert invitation.revoked?
        end

        test "revokes invitations sent to and accepted by another user" do
          user = create(:user, :verified)
          successor = create(:user)
          invitation = create(:successor_invitation, inviter: user, invitee: successor, target: user, accepted_at: Time.now)

          SuccessorInvitation.terminate_all(user)

          invitation.reload
          assert invitation.revoked?
        end
      end

      # most of this logic already tested in single user param case, so only one test case to check filtering
      context "when one user blocks another" do
        test "declines pending invitations when inviter gets blocked" do
          blocker = create(:verified_user)
          blocked = create(:verified_user)
          other = create(:verified_user)

          sent_by_blockee = SuccessorInvitation.create(inviter: blocked, invitee: blocker, target: blocked)
          sent_by_other = SuccessorInvitation.create(inviter: other, invitee: blocker, target: other)

          SuccessorInvitation.terminate_all(blocker, blocked)

          sent_by_blockee.reload
          assert sent_by_blockee.declined?
          assert sent_by_other.pending?
        end
      end
    end

    test "invites are rate limited if rate-limiting is enabled" do
      enable_content_creation_rate_limiting
      expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
      limit = 2

      with_monolith_rate_limiter_redis_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              invite = create(:successor_invitation, :account, inviter: @inviter, invitee: @invitee)
              assert_empty invite.errors
              invite.destroy!
            end

            invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)

            refute invite.save
            assert_equal expected_errors, invite.errors.full_messages
          end
        end
      end
    end

    test "invites are not rate limited if rate-limiting is disabled" do
      GitHub.stubs(:content_creation_rate_limiting_enabled?).returns(false)
      limit = 2

      with_monolith_rate_limiter_redis_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              invite = create(:successor_invitation, :account, inviter: @inviter, invitee: @invitee)
              assert_empty invite.errors
              invite.destroy!
            end

            invite = SuccessorInvitation.new(inviter: @inviter, invitee: @invitee, target: @inviter)

            assert invite.save
          end
        end
      end
    end

    context "audit log event" do
      test "is created when invite is created" do
        events = subscribe "successor_invitation.create"

        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)

        expected_payload = {
          inviter: @inviter.login,
          inviter_id: @inviter.id,
          invitee: @invitee.login,
          invitee_id: @invitee.id,
          target: @inviter.login,
          target_id: @inviter.id
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "is created when invite is destroyed" do
        events = subscribe "successor_invitation.destroy"

        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
        invite.destroy!

        expected_payload = {
          inviter: @inviter.login,
          inviter_id: @inviter.id,
          invitee: @invitee.login,
          invitee_id: @invitee.id,
          target: @inviter.login,
          target_id: @inviter.id
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "is created when invite is accepted" do
        events = subscribe "successor_invitation.accept"

        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
        invite.accept(actor: @invitee)

        expected_payload = {
          inviter: @inviter.login,
          inviter_id: @inviter.id,
          invitee: @invitee.login,
          invitee_id: @invitee.id,
          target: @inviter.login,
          target_id: @inviter.id
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "is created when invite is declined" do
        events = subscribe "successor_invitation.decline"

        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
        invite.decline(actor: @invitee)

        expected_payload = {
          inviter: @inviter.login,
          inviter_id: @inviter.id,
          invitee: @invitee.login,
          invitee_id: @invitee.id,
          target: @inviter.login,
          target_id: @inviter.id
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "is created when invite is cancelled" do
        events = subscribe "successor_invitation.cancel"

        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
        invite.cancel(actor: @inviter)

        expected_payload = {
          inviter: @inviter.login,
          inviter_id: @inviter.id,
          invitee: @invitee.login,
          invitee_id: @invitee.id,
          target: @inviter.login,
          target_id: @inviter.id
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "is created when invite is revoked" do
        events = subscribe "successor_invitation.revoke"

        invite = SuccessorInvitation.create(inviter: @inviter, invitee: @invitee, target: @inviter)
        invite.accept(actor: @invitee)
        invite.revoke(actor: @inviter)

        expected_payload = {
          inviter: @inviter.login,
          inviter_id: @inviter.id,
          invitee: @invitee.login,
          invitee_id: @invitee.id,
          target: @inviter.login,
          target_id: @inviter.id
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
