# typed: true
# frozen_string_literal: true

require "test_helper"

class AdvisoryCreditTest < GitHub::TestCase
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @viewer = create(:verified_user)
  end

  def create_writable_repository_advisory
    repository_advisory = create(:repository_advisory)
    repository_advisory.add_collaborator(@viewer)

    assert repository_advisory.readable_by?(@viewer)
    assert repository_advisory.writable_by?(@viewer)
    repository_advisory
  end

  def create_readable_repository_advisory
    repository = create(:private_repository)
    repository_advisory = create(:published_repository_advisory, {
      repository: repository,
    })
    repository.add_member(@viewer)

    assert repository_advisory.readable_by?(@viewer)
    refute repository_advisory.writable_by?(@viewer)
    repository_advisory
  end

  def create_public_repository_advisory
    repository = create(:public_repository)
    repository_advisory = create(:published_repository_advisory, {
      repository: repository,
    })

    assert repository_advisory.readable_by?(nil)
    refute repository_advisory.writable_by?(nil)
    repository_advisory
  end

  def create_unreadable_repository_advisory
    repository_advisory = create(:repository_advisory)

    refute repository_advisory.readable_by?(@viewer)
    refute repository_advisory.writable_by?(@viewer)
    repository_advisory
  end

  def create_readable_vulnerability
    vulnerability = create(:published_vulnerability)

    assert vulnerability.readable_by?(@viewer)
    vulnerability
  end

  def create_unreadable_vulnerability
    vulnerability = create(:vulnerability, :preview)

    refute vulnerability.readable_by?(@viewer)
    vulnerability
  end

  def last_hydro_message_payload(schema:)
    message = hydro_publisher.sink.messages.reverse_each.detect { |message| message.schema == schema }
    message&.data && decode_hydro_message(message.data)&.message
  end

  context "#readable_by?" do
    context "when accepted" do
      test "is true for a writable repository advisory and a readable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_writable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a writable repository advisory and an unreadable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_writable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a writable repository advisory and no vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_writable_repository_advisory,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a readable repository advisory and a readable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a readable repository advisory and an unreadable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a readable repository advisory and no vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_readable_repository_advisory,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for an unreadable repository advisory and a readable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_unreadable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and an unreadable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_unreadable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and no vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_unreadable_repository_advisory,
        })

        assert_equal false, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is true for no repository advisory and a readable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "is false for no repository advisory and an unreadable vulnerability" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, accepted_advisory_credit.readable_by?(@viewer)
      end

      test "can return true when given a nil actor" do
        accepted_advisory_credit = create(:advisory_credit, :accepted, {
          repository_advisory: create_public_repository_advisory,
        })

        assert_equal true, accepted_advisory_credit.readable_by?(nil)
      end

      test "can return true when creator is deleted" do
        repository_advisory = create_public_repository_advisory
        creator = create(:user)
        credit = create(:advisory_credit, :accepted, creator: creator, repository_advisory: repository_advisory)

        creator.delete

        assert_equal true, credit.reload.readable_by?(@viewer)
      end

      test "can return true when recipient is deleted" do
        repository_advisory = create_public_repository_advisory
        recipient = create(:user)
        credit = create(:advisory_credit, :accepted, recipient: recipient, repository_advisory: repository_advisory)

        recipient.delete

        assert_equal true, credit.reload.readable_by?(@viewer)
      end
    end

    context "when pending" do
      test "is true for a writable repository advisory and a readable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_writable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a writable repository advisory and an unreadable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_writable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal true, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a writable repository advisory and no vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_writable_repository_advisory,
        })

        assert_equal true, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for a readable repository advisory and a readable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for a readable repository advisory and an unreadable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for a readable repository advisory and no vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_readable_repository_advisory,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and a readable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_unreadable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and an unreadable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_unreadable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and no vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_unreadable_repository_advisory,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for no repository advisory and a readable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          vulnerability: create_readable_vulnerability,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end

      test "is false for no repository advisory and an unreadable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, pending_advisory_credit.readable_by?(@viewer)
      end
    end

    context "when declined" do
      test "is true for a writable repository advisory and a readable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_writable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a writable repository advisory and an unreadable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_writable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal true, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is true for a writable repository advisory and no vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_writable_repository_advisory,
        })

        assert_equal true, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for a readable repository advisory and a readable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for a readable repository advisory and an unreadable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for a readable repository advisory and no vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_readable_repository_advisory,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and a readable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_unreadable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and an unreadable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_unreadable_repository_advisory,
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for an unreadable repository advisory and no vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_unreadable_repository_advisory,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for no repository advisory and a readable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          vulnerability: create_readable_vulnerability,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end

      test "is false for no repository advisory and an unreadable vulnerability" do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          vulnerability: create_unreadable_vulnerability,
        })

        assert_equal false, declined_advisory_credit.readable_by?(@viewer)
      end
    end

    context "when viewed by credited user" do
      test "is true for declined credit on a readable repository advisory and a readable vulnerability " do
        declined_advisory_credit = create(:advisory_credit, :declined, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, declined_advisory_credit.readable_by?(declined_advisory_credit.recipient)
      end

      test "is true for pending credit on a readable repository advisory and a readable vulnerability" do
        pending_advisory_credit = create(:advisory_credit, :pending, {
          repository_advisory: create_readable_repository_advisory,
          vulnerability: create_readable_vulnerability,
        })

        assert_equal true, pending_advisory_credit.readable_by?(pending_advisory_credit.recipient)
      end
    end

    # Spammy checks are not enabled for GHES
    unless GitHub.enterprise?
      context "when spammy user is credited on repository advisory" do
        test "is true when viewed by spammy user" do
          repository_advisory = create_public_repository_advisory
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, recipient_id: spammy_user.id, repository_advisory: repository_advisory)

          assert_equal true, credit.readable_by?(spammy_user)
        end

        test "is false when viewed by random user" do
          repository_advisory = create_public_repository_advisory
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, recipient_id: spammy_user.id, repository_advisory: repository_advisory)

          assert_equal false, credit.readable_by?(create(:user))
        end

        test "is true when viewed by collaborator" do
          repository_advisory = create_public_repository_advisory
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, recipient_id: spammy_user.id, repository_advisory: repository_advisory)
          collaborator = create(:user)
          credit.repository_advisory.add_collaborator(collaborator)

          assert_equal true, credit.readable_by?(collaborator)
        end
      end

      context "when spammy user created a credit on repository advisory" do
        test "is true when viewed by spammy user as collaborator" do
          repository_advisory = create_public_repository_advisory
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, repository_advisory: repository_advisory, creator: spammy_user)
          credit.repository_advisory.add_collaborator(spammy_user)

          assert_equal true, credit.readable_by?(spammy_user)
        end

        test "is false when viewed by random user" do
          repository_advisory = create_public_repository_advisory
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, repository_advisory: repository_advisory, creator: spammy_user)

          assert_equal false, credit.readable_by?(create(:user))
        end

        test "is true when viewed by another collaborator" do
          repository_advisory = create_public_repository_advisory
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, repository_advisory: repository_advisory, creator: spammy_user)
          collaborator = create(:user)
          credit.repository_advisory.add_collaborator(collaborator)

          assert_equal true, credit.readable_by?(collaborator)
        end

        test "can return false when recipient is deleted" do
          repository_advisory = create_public_repository_advisory
          creator = create(:spammy_user)
          recipient = create(:user)
          credit = create(:advisory_credit, :accepted, creator: creator, recipient: recipient, repository_advisory: repository_advisory)

          recipient.delete

          assert_equal false, credit.reload.readable_by?(@viewer)
        end
      end

      context "when spammy user is credited on vulnerability" do
        test "is true when viewed by spammy user" do
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, recipient_id: spammy_user.id, vulnerability: create_readable_vulnerability)

          assert_equal true, credit.readable_by?(spammy_user)
        end

        test "is false when viewed by random user" do
          spammy_user = create(:spammy_user)
          credit = create(:advisory_credit, :accepted, recipient_id: spammy_user.id, vulnerability: create_readable_vulnerability)

          assert_equal false, credit.readable_by?(create(:user))
        end
      end
    end
  end

  context "#accept" do
    test "sets accepted_at on a pending credit" do
      Timecop.freeze do
        credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

        credit.accept(actor: credit.recipient)

        refute_predicate credit, :pending?
        assert_predicate credit, :accepted?
        refute_predicate credit, :declined?
        assert_in_delta Time.current, credit.accepted_at, 2.seconds
      end
    end

    test "sets accepted_at on a declined credit" do
      Timecop.freeze do
        credit = create(:advisory_credit, :declined, :with_published_repository_advisory)

        credit.accept(actor: credit.recipient)

        refute_predicate credit, :pending?
        assert_predicate credit, :accepted?
        refute_predicate credit, :declined?
        assert_in_delta Time.current, credit.accepted_at, 2.seconds
      end
    end

    test "only allows the credited user to accept" do
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)
      imposter = create(:user)

      assert_raises AdvisoryCredit::UnauthorizedActorError do
        credit.accept(actor: imposter)
      end

      assert_predicate credit, :pending?
      refute_predicate credit, :accepted?
      refute_predicate credit, :declined?
    end

    test "does nothing if the credit is already accepted" do
      Timecop.freeze do
        original_accepted_at = 2.minutes.ago
        credit = create(:advisory_credit, :accepted, :with_published_repository_advisory, {
          accepted_at: original_accepted_at,
        })

        credit.accept(actor: credit.recipient)

        refute_predicate credit, :pending?
        assert_predicate credit, :accepted?
        refute_predicate credit, :declined?
        assert_in_delta original_accepted_at, credit.accepted_at, 2.seconds
      end
    end

    test "does nothing if the credit was accepted in a race condition" do
      Timecop.freeze do
        original_accepted_at = 2.minutes.ago
        credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

        # Simulate another request accepting the credit, changing the underlying
        # data without our in-memory AdvisoryCredit knowing.
        AdvisoryCredit.
          where(id: credit.id).
          update_all(accepted_at: original_accepted_at)

        credit.accept(actor: credit.recipient)

        refute_predicate credit, :pending?
        assert_predicate credit, :accepted?
        refute_predicate credit, :declined?
        assert_in_delta original_accepted_at, credit.accepted_at, 2.seconds
      end
    end

    test "creates a repository advisory event for an accepted credit associated with a repository advisory" do
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)
      assert_equal 1, RepositoryAdvisoryEvent.count

      assert_difference -> { RepositoryAdvisoryEvent.count }, 1 do
        credit.accept(actor: credit.recipient)
      end

      event = RepositoryAdvisoryEvent.last
      assert_equal credit.repository_advisory, T.must(event).repository_advisory
      assert_equal credit.recipient, T.must(event).actor
      assert_equal "credit_accepted", T.must(event).event
      assert_equal "credit", T.must(event).changed_attribute
      assert_equal credit.accepted_at, T.must(event).created_at
    end

    test "creates a repository advisory event for a declined credit associated with a repository advisory" do
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)
      assert_equal 1, RepositoryAdvisoryEvent.count

      assert_difference -> { RepositoryAdvisoryEvent.count }, 1 do
        credit.decline(actor: credit.recipient)
      end

      event = RepositoryAdvisoryEvent.last
      assert_equal credit.repository_advisory, T.must(event).repository_advisory
      assert_equal credit.recipient, T.must(event).actor
      assert_equal "credit_declined", T.must(event).event
      assert_equal "credit", T.must(event).changed_attribute
      assert_equal credit.declined_at, T.must(event).created_at
    end
  end

  context "#decline" do
    test "sets declined_at on a pending credit" do
      Timecop.freeze do
        credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

        credit.decline(actor: credit.recipient)

        refute_predicate credit, :pending?
        refute_predicate credit, :accepted?
        assert_predicate credit, :declined?
        assert_in_delta Time.current, credit.declined_at, 2.seconds
      end
    end

    test "sets declined_at on an accepted credit" do
      Timecop.freeze do
        credit = create(:advisory_credit, :accepted, :with_published_repository_advisory)

        credit.decline(actor: credit.recipient)

        refute_predicate credit, :pending?
        refute_predicate credit, :accepted?
        assert_predicate credit, :declined?
        assert_in_delta Time.current, credit.declined_at, 2.seconds
      end
    end

    test "only allows the credited user to decline" do
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)
      imposter = create(:user)

      assert_raises AdvisoryCredit::UnauthorizedActorError do
        credit.decline(actor: imposter)
      end

      assert_predicate credit, :pending?
      refute_predicate credit, :accepted?
      refute_predicate credit, :declined?
    end

    test "does nothing if the credit is already declined" do
      Timecop.freeze do
        original_declined_at = 2.minutes.ago
        credit = create(:advisory_credit, :declined, :with_published_repository_advisory, {
          declined_at: original_declined_at,
        })

        credit.decline(actor: credit.recipient)

        refute_predicate credit, :pending?
        refute_predicate credit, :accepted?
        assert_predicate credit, :declined?
        assert_in_delta original_declined_at, credit.declined_at, 2.seconds
      end
    end

    test "does nothing if the credit was declined in a race condition" do
      Timecop.freeze do
        original_declined_at = 2.minutes.ago
        credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

        # Simulate another request declining the credit, changing the underlying
        # data without our in-memory AdvisoryCredit knowing.
        AdvisoryCredit.
          where(id: credit.id).
          update_all(declined_at: original_declined_at)

        credit.decline(actor: credit.recipient)

        refute_predicate credit, :pending?
        refute_predicate credit, :accepted?
        assert_predicate credit, :declined?
        assert_in_delta original_declined_at, credit.declined_at, 2.seconds
      end
    end
  end

  context "instrumentation" do
    test "creating an advisory credit is instrumented" do
      events = subscribe("advisory_credit.create")
      repository_advisory = create(:repository_advisory)
      credit = build(:advisory_credit, repository_advisory: repository_advisory, creator: create(:user))

      assert_difference -> { events.count }, 1 do
        credit.save!
      end

      event = events.last
      assert_equal "advisory_credit.create", event.name
      assert_equal credit.id, event.payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, event.payload[:ghsa_id]
      assert_equal credit.recipient_id, event.payload[:recipient_id]
      assert_equal credit.creator_id, event.payload[:creator_id]
    end

    test "creating an advisory credit is published to Hydro", skip_enterprise: true do
      schema = "github.security_advisories.v0.AdvisoryCreditCreate"
      repository_advisory = create(:repository_advisory)
      credit = create(:advisory_credit, repository_advisory: repository_advisory)
      assert_hydro_messages(count: 1, schema: schema)
      payload = last_hydro_message_payload(schema: schema)
      assert_equal credit.id, payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, payload[:ghsa_id]
      assert_equal credit.recipient_id, payload.dig(:advisory_credit_recipient, :id)
      assert_equal credit.creator_id, payload.dig(:advisory_credit_creator, :id)
    end

    test "creating an advisory credit is audit logged", skip_enterprise: true do
      credit = T.let(nil, T.nilable(AdvisoryCredit))
      repository_advisory = create(:repository_advisory)
      events = assert_performed_audit_entries(
        count: 1,
        only: "advisory_credit.create"
      ) do
        credit = create(:advisory_credit, repository_advisory: repository_advisory)
      end

      assert_subset_hash({ advisory_credit_id: T.must(credit).id }, events.last)
    end

    test "destroying an advisory credit is instrumented" do
      events = subscribe("advisory_credit.destroy")
      credit = create(:advisory_credit, :with_published_repository_advisory)

      assert_difference -> { events.count }, 1 do
        credit.destroy!
      end

      event = events.last
      assert_equal "advisory_credit.destroy", event.name
      assert_equal credit.id, event.payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, event.payload[:ghsa_id]
      assert_equal credit.recipient_id, event.payload[:recipient_id]
      assert_equal credit.creator_id, event.payload[:creator_id]
    end

    test "destroying an advisory credit is published to Hydro", skip_enterprise: true do
      schema = "github.security_advisories.v0.AdvisoryCreditDestroy"
      credit = create(:advisory_credit, :declined, :with_published_repository_advisory)

      credit.destroy!

      assert_hydro_messages(count: 1, schema: schema)
      payload = last_hydro_message_payload(schema: schema)
      assert_equal credit.id, payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, payload[:ghsa_id]
      assert_equal credit.recipient_id, payload.dig(:advisory_credit_recipient, :id)
      assert_equal credit.creator_id, payload.dig(:advisory_credit_creator, :id)
      assert_equal :DECLINED, payload[:advisory_credit_current_state]
    end

    test "destroying an advisory credit is audit logged", skip_enterprise: true do
      credit = create(:advisory_credit, :with_published_repository_advisory)

      events = assert_performed_audit_entries(
        count: 1,
        only: "advisory_credit.destroy"
      ) do
        credit.destroy!
      end

      assert_subset_hash({ advisory_credit_id: credit.id }, events.last)
    end

    test "accepting an advisory credit is instrumented" do
      events = subscribe("advisory_credit.accept")
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

      assert_difference -> { events.count }, 1 do
        credit.accept(actor: credit.recipient)
      end

      event = events.last
      assert_equal "advisory_credit.accept", event.name
      assert_equal credit.id, event.payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, event.payload[:ghsa_id]
      assert_equal credit.recipient_id, event.payload[:recipient_id]
      assert_equal credit.creator_id, event.payload[:creator_id]
    end

    test "accepting an advisory credit is not instrumented if already accepted" do
      events = subscribe("advisory_credit.accept")
      credit = create(:advisory_credit, :accepted, :with_published_repository_advisory)

      assert_no_difference -> { events.count } do
        credit.accept(actor: credit.recipient)
      end
    end

    test "accepting an advisory credit is published to Hydro", skip_enterprise: true do
      schema = "github.security_advisories.v0.AdvisoryCreditAccept"
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

      credit.accept(actor: credit.recipient)

      assert_hydro_messages(count: 1, schema: schema)
      payload = last_hydro_message_payload(schema: schema)
      assert_equal credit.id, payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, payload[:ghsa_id]
      assert_equal credit.recipient_id, payload.dig(:advisory_credit_recipient, :id)
      assert_equal credit.creator_id, payload.dig(:advisory_credit_creator, :id)
    end

    test "accepting an advisory credit is audit logged", skip_enterprise: true do
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

      events = assert_performed_audit_entries(
        count: 1,
        only: "advisory_credit.accept"
      ) do
        credit.accept(actor: credit.recipient)
      end

      assert_subset_hash({ advisory_credit_id: credit.id }, events.last)
    end

    test "auto-accepting an advisory credit is instrumented" do
      events = subscribe("advisory_credit.accept")
      user = create(:user)
      credit = build(:advisory_credit, :pending, :with_published_repository_advisory, {
        creator: user,
        recipient: user,
      })

      assert_difference -> { events.count }, 1 do
        credit.save!
      end

      event = events.last
      assert_equal "advisory_credit.accept", event.name
      assert_equal credit.id, event.payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, event.payload[:ghsa_id]
      assert_equal user.id, event.payload[:recipient_id]
      assert_equal user.id, event.payload[:creator_id]
    end

    test "auto-accepting an advisory credit is published to Hydro", skip_enterprise: true do
      schema = "github.security_advisories.v0.AdvisoryCreditAccept"
      user = create(:user)
      credit = build(:advisory_credit, :pending, :with_published_repository_advisory, {
        creator: user,
        recipient: user,
      })

      credit.save!

      assert_hydro_messages(count: 1, schema: schema)
      payload = last_hydro_message_payload(schema: schema)
      assert_equal credit.id, payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, payload[:ghsa_id]
      assert_equal user.id, payload.dig(:advisory_credit_recipient, :id)
      assert_equal user.id, payload.dig(:advisory_credit_creator, :id)
    end

    test "auto-accepting an advisory credit is audit logged", skip_enterprise: true do
      user = create(:user)
      credit = build(:advisory_credit, :pending, :with_published_repository_advisory, {
        creator: user,
        recipient: user,
      })

      events = assert_performed_audit_entries(
        count: 1,
        only: "advisory_credit.accept"
      ) do
        credit.save!
      end

      assert_subset_hash({ advisory_credit_id: credit.id }, events.last)
    end

    test "declining an advisory credit is instrumented" do
      events = subscribe("advisory_credit.decline")
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

      assert_difference -> { events.count }, 1 do
        credit.decline(actor: credit.recipient)
      end

      event = events.last
      assert_equal "advisory_credit.decline", event.name
      assert_equal credit.id, event.payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, event.payload[:ghsa_id]
      assert_equal credit.recipient_id, event.payload[:recipient_id]
      assert_equal credit.creator_id, event.payload[:creator_id]
    end

    test "declining an advisory credit is not instrumented if already declined" do
      events = subscribe("advisory_credit.decline")
      credit = create(:advisory_credit, :declined, :with_published_repository_advisory)

      assert_no_difference -> { events.count } do
        credit.decline(actor: credit.recipient)
      end
    end

    test "declining an advisory credit is published to Hydro", skip_enterprise: true do
      schema = "github.security_advisories.v0.AdvisoryCreditDecline"
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

      credit.decline(actor: credit.recipient)

      assert_hydro_messages(count: 1, schema: schema)
      payload = last_hydro_message_payload(schema: schema)
      assert_equal credit.id, payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, payload[:ghsa_id]
      assert_equal credit.recipient_id, payload.dig(:advisory_credit_recipient, :id)
      assert_equal credit.creator_id, payload.dig(:advisory_credit_creator, :id)
    end

    test "declining an advisory credit is audit logged", skip_enterprise: true do
      credit = create(:advisory_credit, :pending, :with_published_repository_advisory)

      events = assert_performed_audit_entries(
        count: 1,
        only: "advisory_credit.decline"
      ) do
        credit.decline(actor: credit.recipient)
      end

      assert_subset_hash({ advisory_credit_id: credit.id }, events.last)
    end

    test "sending a notification about an advisory credit is instrumented" do
      events = subscribe("advisory_credit.notify")
      credit = create(:advisory_credit, :pending, :not_notified, :with_published_repository_advisory)
      assert credit.deliver_notifications?

      assert_difference -> { events.count }, 1 do
        credit.deliver_notifications
      end

      event = events.last
      assert_equal "advisory_credit.notify", event.name
      assert_equal credit.id, event.payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, event.payload[:ghsa_id]
      assert_equal credit.recipient_id, event.payload[:recipient_id]
      assert_equal credit.creator_id, event.payload[:creator_id]
    end

    test "sending a notification about an advisory credit is not instrumented if already notified" do
      events = subscribe("advisory_credit.notify")
      credit = create(:advisory_credit, :pending, :notified, :with_published_repository_advisory)
      refute credit.deliver_notifications?

      assert_no_difference -> { events.count } do
        credit.deliver_notifications
      end
    end

    test "sending a notification about an advisory credit is published to Hydro", skip_enterprise: true do
      schema = "github.security_advisories.v0.AdvisoryCreditNotify"
      credit = create(:advisory_credit, :pending, :not_notified, :with_published_repository_advisory)
      assert credit.deliver_notifications?

      credit.deliver_notifications

      assert_hydro_messages(count: 1, schema: schema)
      payload = last_hydro_message_payload(schema: schema)
      assert_equal credit.id, payload[:advisory_credit_id]
      assert_equal credit.ghsa_id, payload[:ghsa_id]
      assert_equal credit.recipient_id, payload.dig(:advisory_credit_recipient, :id)
      assert_equal credit.creator_id, payload.dig(:advisory_credit_creator, :id)
    end
  end

  context "#deliver_notifications?" do
    test "returns true for a pending credit on a readable repository advisory" do
      credited_user = create(:user)
      advisory = create(:published_repository_advisory)
      assert advisory.readable_by?(credited_user)

      credit = create(:advisory_credit, :pending, :not_notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: advisory.owner,
      })

      assert credit.deliver_notifications?
    end

    test "returns false when the credit's notification was already delivered" do
      credited_user = create(:user)
      advisory = create(:published_repository_advisory)
      assert advisory.readable_by?(credited_user)

      credit = create(:advisory_credit, :pending, :notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: advisory.owner,
      })

      refute credit.deliver_notifications?
    end

    test "returns false when crediting yourself" do
      credited_user = create(:user)
      advisory = create(:published_repository_advisory)
      advisory.add_collaborator(credited_user)
      assert advisory.writable_by?(credited_user)

      credit = create(:advisory_credit, :pending, :not_notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: credited_user,
      })

      refute credit.deliver_notifications?
    end

    test "returns false if the repository advisory is unreadable" do
      credited_user = create(:user)
      advisory = create(:draft_repository_advisory)
      refute advisory.readable_by?(credited_user)

      credit = create(:advisory_credit, :pending, :not_notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: advisory.owner,
      })

      refute credit.deliver_notifications?
    end

    test "returns false if the credit is accepted" do
      credited_user = create(:user)
      advisory = create(:published_repository_advisory)
      assert advisory.readable_by?(credited_user)

      credit = create(:advisory_credit, :accepted, :not_notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: advisory.owner,
      })

      refute credit.deliver_notifications?
    end

    test "returns false if the credit is declined" do
      credited_user = create(:user)
      advisory = create(:published_repository_advisory)
      assert advisory.readable_by?(credited_user)

      credit = create(:advisory_credit, :declined, :not_notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: advisory.owner,
      })

      refute credit.deliver_notifications?
    end

    test "returns false if the credited user is missing" do
      credited_user = create(:user)
      advisory = create(:published_repository_advisory)
      assert advisory.readable_by?(credited_user)
      credit = create(:advisory_credit, :pending, :not_notified, {
        repository_advisory: advisory,
        recipient: credited_user,
        creator: advisory.owner,
      })

      assert_changes -> { credit.reload.deliver_notifications? }, from: true, to: false do
        credited_user.delete
      end
    end
  end

  context "#deliver_notifications" do
    test "enqueues a Newsies delivery job if a notification should be delivered" do
      credit = create(:advisory_credit, :pending, :not_notified, :with_published_repository_advisory)
      assert credit.deliver_notifications?

      assert_enqueued_jobs(1, only: [Newsies::DeliverNotificationsJob]) do
        credit.deliver_notifications
      end
    end

    test "enqueues nothing if a notification should not be delivered" do
      credit = create(:advisory_credit, :accepted, :not_notified, :with_published_repository_advisory)
      refute credit.deliver_notifications?

      assert_no_enqueued_jobs(only: [Newsies::DeliverNotificationsJob]) do
        credit.deliver_notifications
      end
    end

    test "marks the credits as notified if a notification should be delivered" do
      credit = create(:advisory_credit, :pending, :not_notified, :with_published_repository_advisory)
      assert credit.deliver_notifications?

      assert_changes -> { credit.notified? }, from: false, to: true do
        credit.deliver_notifications
      end

      assert_in_delta credit.notified_at, Time.current, 2.seconds
    end

    test "does not mark the credit as notified if a notification should not be delivered" do
      credit = create(:advisory_credit, :accepted, :not_notified, :with_published_repository_advisory)
      refute credit.deliver_notifications?

      assert_no_changes -> { credit.notified? }, from: false do
        credit.deliver_notifications
      end

      assert_nil credit.notified_at
    end
  end

  context "credit events" do
    test "for assignment are created when you create an advisory credit" do
      repository_advisory = create(:repository_advisory)
      assert_equal 0, repository_advisory.events.count

      advisory_credit = create(:advisory_credit, repository_advisory: repository_advisory)

      assert_equal 1, repository_advisory.events.count
      event = repository_advisory.events.first
      assert_equal advisory_credit.creator, event.actor
      assert_equal advisory_credit.recipient, event.subject
      assert_equal "credit_assigned", event.event
      assert_equal "credit", event.changed_attribute
      assert_equal advisory_credit.created_at, event.created_at
      assert_equal advisory_credit.credit_type, event.value_is
    end

    test "for unassignment are created when you destroy an advisory credit" do
      repository_advisory = create(:repository_advisory)
      advisory_credit = create(:advisory_credit, repository_advisory: repository_advisory)
      assert_equal 1, repository_advisory.events.count

      right_now = Time.now.change(usec: 0).utc
      Timecop.freeze(right_now) do
        advisory_credit.destroy
      end

      assert_equal 2, repository_advisory.events.count
      event = repository_advisory.events.second
      assert_equal advisory_credit.creator, event.actor
      assert_equal advisory_credit.recipient, event.subject
      assert_equal "credit_unassigned", event.event
      assert_equal "credit", event.changed_attribute
      assert_equal right_now, event.created_at
      assert_equal advisory_credit.credit_type, event.value_is
    end

    test "for assignment and unassignment are not created when there is no associated repository advisory" do
      advisory_credit = create(:advisory_credit, :with_vulnerability, repository_advisory: nil)

      assert_equal 0, RepositoryAdvisoryEvent.count
    end

    test "for type change are created when you update an advisory credit with a different credit type" do
      repository_advisory = create(:repository_advisory)
      advisory_credit = create(:advisory_credit, repository_advisory: repository_advisory)
      previous_credit_type = advisory_credit.credit_type

      assert_difference -> { repository_advisory.events.count }, 1 do
        advisory_credit.update!(credit_type: "reporter")
      end

      refute_equal previous_credit_type, advisory_credit.credit_type
      event = repository_advisory.events.second
      assert_equal advisory_credit.recipient, event.subject
      assert_equal advisory_credit.creator, event.actor
      assert_equal "credit_type_changed", event.name
      assert_equal "credit", event.changed_attribute
      assert_equal advisory_credit.updated_at, event.created_at
      assert_equal advisory_credit.credit_type, event.value_is
      assert_equal previous_credit_type, event.value_was
    end

    test "for type change are not created when you update an advisory credit, but keep the same credit type" do
      repository_advisory = create(:repository_advisory)
      advisory_credit = create(:advisory_credit, repository_advisory: repository_advisory)

      assert_no_difference -> { RepositoryAdvisoryEvent.count } do
        advisory_credit.touch
      end
    end

    test "for type change are not created when there is no associated repository advisory" do
      advisory_credit = create(:advisory_credit, :with_vulnerability, repository_advisory: nil)

      assert_no_difference -> { RepositoryAdvisoryEvent.count } do
        advisory_credit.touch
      end
    end
  end

  context "credited users" do
    test "can not be given credit if they block advisory creator" do
      blocked_creator = create(:verified_user)
      blocking_user = create(:user)
      blocking_user.block(blocked_creator)

      credit = build(:advisory_credit, :with_published_repository_advisory, creator: blocked_creator, recipient_id: blocking_user.id)

      refute_predicate credit, :valid?
      assert_includes credit.errors[:creator], "cannot give credit at this time"
    end

    test "auto-accept the credit if they are also its creator" do
      user = create(:user)
      advisory = create(:repository_advisory)
      credit = build(:advisory_credit, :pending, {
        repository_advisory: advisory,
        creator: user,
        recipient: user,
      })

      assert_difference -> { advisory.events.count }, 1 do
        assert_changes -> { credit.accepted? }, from: false, to: true do
          credit.save!
        end
      end
    end

    test "do not auto-accept the credit if the advisory is a private vulnerability disclosure and the recipient is the author" do
      user = create(:user)
      advisory = create(:pending_pvd_repo_advisory, author: user)
      credit = build(:advisory_credit, :pending, {
        repository_advisory: advisory,
        creator: user,
        recipient: user,
      })

      assert_difference -> { advisory.events.count }, 1 do
        assert_no_changes -> { credit.accepted? } do
          credit.save!
        end
      end
    end
  end

  context "rate limits" do
    test "rate limits are present so too many records can't be created within a certain period of time when rate limiting is enabled" do
      enable_content_creation_rate_limiting

      limit = 2
      creator = create(:user)

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            limit.times do
              advisory_credit = build(:advisory_credit, :pending, :with_published_repository_advisory, creator: creator)
              assert advisory_credit.save
            end

            another_advisory_credit = build(:advisory_credit, :pending, :with_published_repository_advisory, creator: creator)
            refute another_advisory_credit.save
            assert_equal ["was submitted too quickly"], another_advisory_credit.errors.full_messages
          end
        end
      end
    end

    test "are not present for the creation of advisory credits when rate limiting is disabled" do
      disable_content_creation_rate_limiting
      limit = 2
      creator = create(:user)

      with_cache_enabled do
        Timecop.freeze do
          GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
            (limit + 1).times do
              advisory_credit = build(:advisory_credit, :pending, :with_published_repository_advisory, creator: creator)
              assert advisory_credit.save
            end
          end
        end
      end
    end
  end

  context "#target_for_conditional_access" do
    test "returns the repo owner when available" do
      credit = create(:advisory_credit, :with_published_repository_advisory)
      refute_nil credit.repository_advisory.repository.owner
      assert_equal credit.repository_advisory.repository.owner, credit.target_for_conditional_access
    end

    test "returns :no_target_for_conditional_access if there only is a vulnerability attached to it" do
      credit = create(:advisory_credit, :with_published_vulnerability)
      assert_equal :no_target_for_conditional_access, credit.target_for_conditional_access
    end
  end

  context "#async_target_for_conditional_access" do
    test "returns the repo owner when available" do
      credit = create(:advisory_credit, :with_published_repository_advisory)
      refute_nil credit.repository_advisory.repository.owner
      assert_equal credit.repository_advisory.repository.owner, credit.async_target_for_conditional_access.sync
    end

    test "returns :no_target_for_conditional_access if there only is a vulnerability attached to it" do
      credit = create(:advisory_credit, :with_published_vulnerability)
      assert_equal :no_target_for_conditional_access, credit.async_target_for_conditional_access.sync
    end
  end

  context "scoped vulnerabilities" do
    test "can belong to scoped and unscoped vulnerabilities" do
      vuln = create_readable_vulnerability
      credit = create(:advisory_credit, :accepted, vulnerability: vuln)
      scoped_vuln = create(:scoped_vulnerability, id: vuln.id, ghsa_id: vuln.ghsa_id)

      assert_same_elements vuln.credits, scoped_vuln.credits
      assert_nil credit.scoped_vulnerability
      credit.reload
      assert_equal credit.with_scope(:open_source).scoped_vulnerability, scoped_vuln
    end

    test "can belong to innersource vulnerabilities" do
      vuln = create_readable_vulnerability
      credit = create(:advisory_credit, :accepted, vulnerability: vuln)
      scoped_vuln = create(:innersource_vulnerability, id: vuln.id, ghsa_id: vuln.ghsa_id)

      assert_same_elements vuln.credits, scoped_vuln.credits
      assert_nil credit.scoped_vulnerability
      credit.reload
      assert_equal credit.with_scope(:innersource).scoped_vulnerability, scoped_vuln
    end
  end
end
