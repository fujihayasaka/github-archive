# rubocop:disable Naming/InclusiveLanguage
# typed: true
# frozen_string_literal: true

require "test_helper"

class BlacklistedPaymentMethodTest < GitHub::TestCase
  context ".find_by_card_fingerprint" do
    test "it finds the relevant payment_method" do
      paypal_payment_method = create(:blacklisted_payment_method, paypal_email: "user1@example.com", unique_number_identifier: nil)
      unique_number_identifier_payment_method = create(:blacklisted_payment_method, paypal_email: nil, unique_number_identifier: "1234")

      assert_equal paypal_payment_method, BlacklistedPaymentMethod.find_by_card_fingerprint(paypal_payment_method.paypal_email)
      assert_equal unique_number_identifier_payment_method, BlacklistedPaymentMethod.find_by_card_fingerprint(unique_number_identifier_payment_method.unique_number_identifier)
    end
  end

  context ".create_for_all_users" do
    test "creates an entry for all users associated to a blocklisted payment method" do
      user1 = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"

      blocklisted = BlacklistedPaymentMethod.create_for_all_users(user1, user1.payment_method)
      assert_equal 2, blocklisted.size
    end

    test "doesn't attempt to create a blocklisted payment entry for a user if it already exists" do
      Timecop.freeze do
        user1 = create :user_with_payment_identifier, unique_number: "acb123"
        user2 = create :user_with_payment_identifier, unique_number: "acb123"
        user3 = create :user_with_payment_identifier, unique_number: "acb123"
        unrelated_user = create :user_with_payment_identifier, unique_number: "123abc"

        existing_blocklisted_payment_method = BlacklistedPaymentMethod.create_from_user_and_payment_method(user1, user1.payment_method)
        assert existing_blocklisted_payment_method.persisted?
        Timecop.travel(10.minutes)
        newly_blocklisted = BlacklistedPaymentMethod.create_for_all_users(user2, user2.payment_method)

        assert_equal newly_blocklisted.map(&:user_id).sort, [user2.id, user3.id]
      end
    end

  end

  context ".create_from_user_and_payment_method" do
    test "stores unique number identifier for credit card" do
      user = create :user_with_payment_identifier, unique_number: "acb123"
      blacklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method)

      assert blacklisted.persisted?
      assert_equal \
        user.payment_method.unique_number_identifier,
        blacklisted.unique_number_identifier
    end

    test "stores paypal email for paypal" do
      user = create :user_with_payment_identifier, paypal_email: "no@example.com"
      blacklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method)

      assert blacklisted.persisted?
      assert_equal \
        user.payment_method.paypal_email,
        blacklisted.paypal_email
    end

    test "stores reason and consequence when blocklisting a payment method" do
      user = create :user_with_payment_identifier, unique_number: "acb123"
      blacklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked)

      assert blacklisted.persisted?
      assert_equal \
        user.payment_method.unique_number_identifier,
        blacklisted.unique_number_identifier
      assert_equal blacklisted.reason, "fraudulent credit card"
      assert_equal blacklisted.consequence, BlacklistedPaymentMethod::Consequence::BillingLocked.serialize
    end

    test "defaults to latest existing BlacklistedPaymentMethod's consequence and reason if force is false" do
      Timecop.freeze do
        user = create :user_with_payment_identifier, unique_number: "acb123"
        user2 = create :user_with_payment_identifier, unique_number: "acb123"

        blocklisted1 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked)
        Timecop.travel(10.minutes)
        blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, user2.payment_method, reason: "some reason", consequence: BlacklistedPaymentMethod::Consequence::Suspended, force: false)

        assert_equal \
          blocklisted1.unique_number_identifier,
          blocklisted2.unique_number_identifier

        assert_equal blocklisted1.consequence, blocklisted2.consequence
        assert_equal blocklisted1.reason, blocklisted2.reason
      end
    end

    test "uses the consequence and reason provided as an argumeent if force is true" do
      Timecop.freeze do
        user = create :user_with_payment_identifier, unique_number: "acb123"
        user2 = create :user_with_payment_identifier, unique_number: "acb123"
        user3 = create :user_with_payment_identifier, unique_number: "acb123"

        blocklisted1 = BlacklistedPaymentMethod.create_from_user_and_payment_method(
          user,
          user.payment_method,
          reason: "original reason",
          consequence: BlacklistedPaymentMethod::Consequence::Suspended
        )
        Timecop.travel(10.minutes)
        blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(
          user2,
          user2.payment_method,
          reason: "fraudulent credit card",
          consequence: BlacklistedPaymentMethod::Consequence::BillingLocked,
          force: true
        )

        assert_equal \
          blocklisted1.unique_number_identifier,
          blocklisted2.unique_number_identifier

        refute_equal blocklisted1.consequence, blocklisted2.consequence
        refute_equal blocklisted1.reason, blocklisted2.reason
      end
    end

    test "defaults to latest existing BlacklistedPaymentMethod's consequence and reason if none is provided" do
      Timecop.freeze do
        user = create :user_with_payment_identifier, unique_number: "acb123"
        user2 = create :user_with_payment_identifier, unique_number: "acb123"
        user3 = create :user_with_payment_identifier, unique_number: "acb123"

        blocklisted1 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "original reason", consequence: BlacklistedPaymentMethod::Consequence::Suspended)
        Timecop.travel(10.minutes)
        blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, user2.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, force: true)
        Timecop.travel(10.minutes)
        blocklisted3 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user3, user3.payment_method)

        assert_equal \
          blocklisted2.unique_number_identifier,
          blocklisted3.unique_number_identifier

        refute_equal blocklisted1.consequence, blocklisted3.consequence
        assert_equal blocklisted2.consequence, blocklisted3.consequence
        refute_equal blocklisted1.reason, blocklisted3.reason
        assert_equal blocklisted2.reason, blocklisted3.reason
      end
    end

    test "creates audit log entry when creating a blocklisted payment method" do
      events = subscribe "blocklisted_payment_method.add"
      user = create :user_with_payment_identifier, unique_number: "acb123"
      actor = create :user
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: actor)

      expected_payload = {
        consequence: blocklisted.consequence,
        reason: blocklisted.reason,
        actor: actor.login,
        actor_id: actor.id,
        user: user.login,
        user_id: user.id,
      }

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "creates audit log entry when blocklisting a payment method that has already been blocklisted " do
      events = subscribe "blocklisted_payment_method.add"
      user = create :user_with_payment_identifier, unique_number: "acb123"
      actor = create :user
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: actor)
      duplicate = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: actor)

      expected_payload = {
        consequence: blocklisted.consequence,
        reason: blocklisted.reason,
        actor: actor.login,
        actor_id: actor.id,
        user: user.login,
        user_id: user.id,
        error: "Payment method has already been blocklisted",
      }

      assert event = events.pop
      assert_equal expected_payload, event.payload
    end

    test "fails to create blacklisted payment method without an identifier" do
      user = create :user_with_payment_identifier, unique_number: nil
      blacklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method)

      refute blacklisted.persisted?
    end

    test "finds an existing BlacklistedPaymentMethod if one exists" do
      user = create :user_with_payment_identifier, unique_number: "acb123"

      blacklisted1 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method)
      blacklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method)

      assert_equal blacklisted2, blacklisted1
    end

    test "can create a BlacklistedPaymentMethod with the same unique_number" do
      user1 = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"

      assert_difference("BlacklistedPaymentMethod.count", +2) do
        BlacklistedPaymentMethod.create_from_user_and_payment_method(user1, user1.payment_method)
        BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, user2.payment_method)
      end
    end
  end

  context "#users" do
    test "returns all users using the blacklisted payment identifier" do
      user1 = create :user_with_payment_identifier, unique_number: "def456"
      user2 = create :user_with_payment_identifier, paypal_email: "good@example.com"

      user3 = create :user_with_payment_identifier, unique_number: "abc123"
      user4 = create :user_with_payment_identifier, unique_number: "abc123"

      blacklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user3, user3.payment_method)

      assert_includes blacklisted.users, user3
      assert_includes blacklisted.users, user4
      refute_includes blacklisted.users, user1
      refute_includes blacklisted.users, user2
    end

    test "returns all users using the blacklisted paypal id" do
      user1 = create :user_with_payment_identifier, paypal_email: "good@example.com"
      user2 = create :user_with_payment_identifier, unique_number: "abc123"

      user3 = create :user_with_payment_identifier, paypal_email: "bad@example.com"
      user4 = create :user_with_payment_identifier, paypal_email: "bad@example.com"

      blacklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user3, user3.payment_method)

      assert_includes blacklisted.users, user3
      assert_includes blacklisted.users, user4
      refute_includes blacklisted.users, user1
      refute_includes blacklisted.users, user2
    end
  end

  context "#execute_consequence" do
    test "suspends the account if the consequence is suspended" do
      user = create :user_with_payment_identifier, unique_number: "acb123"
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::Suspended)
      blocklisted.execute_consequence

      assert user.reload.suspended?
    end

    test "locks the account's billing if the consequence is billing locked" do
      user = create :user_with_payment_identifier, unique_number: "acb123"
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked)
      blocklisted.execute_consequence

      assert user.reload.disabled?
    end

    test "performs the consequence on the blocklisted payment method on all users if include_all_users is true" do
      user = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"

      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card")

      blocklisted.execute_consequence(include_all_users: true)

      assert user.reload.suspended?
      assert user2.reload.suspended?
    end
  end

  context "#remove_payment_method" do
    test "removes a payment method from the blocklist" do
      actor = create :user
      user = create :user_with_payment_identifier, unique_number: "acb123"
      payment_method = user.payment_method
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, payment_method, reason: "fraudulent credit card")
      assert blocklisted.persisted?
      assert payment_method.blocklisted?

      assert BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: payment_method.card_fingerprint, actor:, reason: "No longer fraudulent")
      refute payment_method.blocklisted?
      refute BlacklistedPaymentMethod.find_by_payment_method(payment_method)
    end

    test "removes all BlacklistedPaymentMethod entries associated with the payment method" do
      actor = create :user
      user = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"
      payment_method = user.payment_method

      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, payment_method, reason: "fraudulent credit card")
      blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, payment_method)
      assert blocklisted.persisted?
      assert blocklisted2.persisted?
      assert payment_method.blocklisted?

      assert BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: payment_method.card_fingerprint, actor:, reason: "no longer fraudulent")
      refute payment_method.blocklisted?
      assert_empty BlacklistedPaymentMethod.find_all_by_card_fingerprint(payment_method.card_fingerprint)
    end

    test "returns false if any of the payment methods was not successfully removed from the blocklist" do
      actor = create :user
      user = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"
      payment_method = user.payment_method
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card")
      blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, user.payment_method, reason: "fraudulent credit card")

      BlacklistedPaymentMethod.stubs(:destroy).returns(false)

      refute BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: payment_method.card_fingerprint, actor:, reason: "no longer fraudulent")
      assert payment_method.blocklisted?
    end

    test "unsuspends of associated accounts if undo_consequence is set to true" do
      actor = create :user
      user = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"
      payment_method = user.payment_method

      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::Suspended)
      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::Suspended)
      blocklisted.execute_consequence(include_all_users: true)
      assert user.reload.suspended?
      assert user2.reload.suspended?

      assert BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: payment_method.card_fingerprint, actor:, reason: "no longer fraudulent", undo_consequence: true)
      refute user.reload.suspended?
      refute user2.reload.suspended?
    end

    test "unlocks billing of associated accounts if undo_consequence is set to true" do
      actor = create :user
      user = create :user_with_payment_identifier, unique_number: "acb123"
      user2 = create :user_with_payment_identifier, unique_number: "acb123"
      payment_method = user.payment_method

      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked)
      BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked)
      blocklisted.execute_consequence(include_all_users: true)
      assert user.reload.disabled?
      assert user2.reload.disabled?

      assert BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: payment_method.card_fingerprint, actor:, reason: "no longer fraudulent", undo_consequence: true)
      refute user.reload.disabled?
      refute user2.reload.disabled?
    end

    test "undos the consequence on accounts for blocklisted payment methods with difference consequences if undo_consequence is set to true" do
      actor = create :user
      suspended_user = create :user_with_payment_identifier, unique_number: "acb123"
      billing_locked_user = create :user_with_payment_identifier, unique_number: "acb123"
      payment_method = suspended_user.payment_method

      blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(billing_locked_user, payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, force: true)
      blocklisted.execute_consequence(include_all_users: false)
      assert billing_locked_user.reload.disabled?
      refute billing_locked_user.reload.suspended?

      blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(suspended_user, payment_method, reason: "fraudulent credit card", force: true, consequence: BlacklistedPaymentMethod::Consequence::Suspended)
      blocklisted2.execute_consequence(include_all_users: false)
      assert suspended_user.reload.suspended?

      assert BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: payment_method.card_fingerprint, actor:, reason: "no longer fraudulent", undo_consequence: true)
      refute suspended_user.reload.suspended?
      refute billing_locked_user.reload.disabled?
    end

    test "creates an audit log entry" do
      Timecop.freeze do
        events = subscribe "blocklisted_payment_method.remove"
        user = create :user_with_payment_identifier, unique_number: "acb123"
        user2 = create :user_with_payment_identifier, unique_number: "acb123"
        actor = create :user
        blocklisted = BlacklistedPaymentMethod.create_from_user_and_payment_method(user, user.payment_method, reason: "fraudulent credit card", consequence: BlacklistedPaymentMethod::Consequence::BillingLocked, actor: actor)
        blocklisted2 = BlacklistedPaymentMethod.create_from_user_and_payment_method(user2, user.payment_method, actor: actor)
        Timecop.travel(10.minutes)
        BlacklistedPaymentMethod.remove_payment_method(card_fingerprint: user.payment_method.card_fingerprint, actor:, reason: "Card was wrongfully blocklisted", undo_consequence: true)

        expected_payload = {
          reason_was: blocklisted.reason,
          consequence_was: blocklisted.consequence,
          removal_reason: "Card was wrongfully blocklisted",
          actor: actor.login,
          actor_id: actor.id,
          user: user2.login,
          user_id: user2.id,
          undo_suspension_or_billing_locked: false,
        }
        assert_equal events.size, 2
        assert event = events.pop
        payload = event.payload
        assert_equal expected_payload[:reason_was], payload[:reason_was]
        assert_equal expected_payload[:consequence_was], payload[:consequence_was]
        assert_equal expected_payload[:removal_reason], payload[:removal_reason]
        assert_equal expected_payload[:actor_id], payload[:actor_id]
      end
    end
  end
end

# rubocop:enable Naming/InclusiveLanguage
