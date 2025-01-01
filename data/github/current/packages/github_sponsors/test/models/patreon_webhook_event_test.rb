# typed: true
# frozen_string_literal: true

require "test_helper"

class PatreonWebhookEventTest < GitHub::TestCase
  include DogstatsTestHelpers

  context ".secret_for" do
    test "returns the secret for matching webhook when there's only a single match" do
      spu = create(:sponsors_patreon_user)
      patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: spu)
      create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu, campaign_id: patreon_tier.campaign_id,
        secret: "foobar", triggers: ["members:create", "members:update"])

      assert_equal "foobar", PatreonWebhookEvent.secret_for(campaign_id: patreon_tier.campaign_id,
        trigger: "members:create")
    end

    test "returns nil when no matching webhook is found" do
      assert_nil PatreonWebhookEvent.secret_for(campaign_id: "somecampaign", trigger: "members:create")
    end

    test "returns nil when matching webhook is found but it does not have the given trigger" do
      spu = create(:sponsors_patreon_user)
      patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: spu)
      create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu,
        campaign_id: patreon_tier.campaign_id, secret: "foobar", triggers: ["members:update"])

      assert_nil PatreonWebhookEvent.secret_for(campaign_id: patreon_tier.campaign_id, trigger: "members:create")
    end

    test "returns secret for the newest webhook when multiple matching webhooks are found for given campaign ID" do
      campaign_id = "somecampaign"
      older_webhook_secret = "older_secret"
      newer_webhook_secret = "newer_secret"
      trigger = "members:create"
      create(:sponsors_patreon_campaign_webhook, campaign_id: campaign_id, secret: older_webhook_secret,
        triggers: [trigger])
      create(:sponsors_patreon_campaign_webhook, campaign_id: campaign_id, secret: newer_webhook_secret,
        triggers: [trigger])

      assert_equal newer_webhook_secret, PatreonWebhookEvent.secret_for(campaign_id: campaign_id, trigger: trigger)
      assert_dogstats_increment(1, "#{PatreonWebhookEvent::DATADOG_PREFIX}.multiple_webhooks_for_campaign")
    end
  end

  if GitHub.sponsors_enabled?
    context ".ours?" do
      test "true when uri and triggers match" do
        uri = "https://github.com/sponsors/patreon_webhook"
        triggers = Set.new(["members:create", "members:update", "members:delete", "members:pledge:create",
          "members:pledge:update", "members:pledge:delete"])
        assert_equal triggers, PatreonWebhookEvent.triggers.to_set, "need the expected set of triggers"

        assert PatreonWebhookEvent.ours?(uri: uri, triggers: triggers)
      end

      test "false when uri does not match" do
        uri = "https://github.com/sponsors"
        triggers = Set.new(["members:create", "members:update", "members:delete", "members:pledge:create",
          "members:pledge:update", "members:pledge:delete"])
        assert_equal triggers, PatreonWebhookEvent.triggers.to_set, "need the expected set of triggers"

        refute PatreonWebhookEvent.ours?(uri: uri, triggers: triggers)
      end

      test "false when triggers do not match" do
        uri = "https://github.com/sponsors/patreon_webhook"
        triggers = Set.new(["members:create"])
        refute_equal triggers, PatreonWebhookEvent.triggers.to_set, "need a different set of triggers than expected"

        refute PatreonWebhookEvent.ours?(uri: uri, triggers: triggers)
      end
    end

    context ".trigger_for_kind" do
      test "returns a trigger for each PatreonWebhookEvent kind" do
        kinds = PatreonWebhookEvent.kinds.keys
        refute_empty kinds

        kinds.each do |kind|
          if kind.to_s == "unknown"
            assert_nil PatreonWebhookEvent.trigger_for_kind(kind)
          else
            refute_nil PatreonWebhookEvent.trigger_for_kind(kind)
          end
        end
      end

      test "returns corresponding trigger for given kind as a Symbol" do
        assert_equal "members:delete", PatreonWebhookEvent.trigger_for_kind(:members_delete)
      end
    end

    context ".kind_for_trigger" do
      test "returns a kind for known Patreon triggers" do
        assert_equal "members_create", PatreonWebhookEvent.kind_for_trigger("members:create")
        assert_equal "members_update", PatreonWebhookEvent.kind_for_trigger("members:update")
        assert_equal "members_delete", PatreonWebhookEvent.kind_for_trigger("members:delete")
        assert_equal "members_pledge_create", PatreonWebhookEvent.kind_for_trigger("members:pledge:create")
        assert_equal "members_pledge_update", PatreonWebhookEvent.kind_for_trigger("members:pledge:update")
        assert_equal "members_pledge_delete", PatreonWebhookEvent.kind_for_trigger("members:pledge:delete")
      end

      test "returns nil for unexpected Patreon trigger" do
        assert_nil PatreonWebhookEvent.kind_for_trigger("foo:bar")
      end
    end

    context "#sponsors_patreon_user" do
      test "returns the SponsorsPatreonUser specified in account_id" do
        spu = create(:sponsors_patreon_user)
        webhook = PatreonWebhookEvent.new(account_id: spu.patreon_user_id)
        assert_equal spu, webhook.sponsors_patreon_user
      end

      test "returns nil when account_id is nil" do
        webhook_event = create(:patreon_webhook_event, :pending, :members_create, account_id: nil)
        assert_nil webhook_event.sponsors_patreon_user
      end
    end

    context "validations" do
      context "kind" do
        test "validates presence" do
          assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Kind can't be blank") do
            PatreonWebhookEvent.new(payload: { test: "dummy" }, status: "pending").save!
          end
        end

        test "accepts key of kind as String" do
          assert_nothing_raised do
            PatreonWebhookEvent.new(kind: "unknown", payload: { test: "dummy" }, status: "pending").save!
          end
        end

        test "validates key of kind as String" do
          assert_raises_with_message(ArgumentError, "'bla' is not a valid kind") do
            PatreonWebhookEvent.new(kind: "bla", payload: { test: "dummy" }, status: "pending").save!
          end
        end

        test "validates inclusion" do
          valid_kinds = PatreonWebhookEvent.kinds.values
          invalid_kind = T.must(valid_kinds.max) + 1

          assert_raises_with_message(ArgumentError, "'#{invalid_kind}' is not a valid kind") do
            PatreonWebhookEvent.new(kind: invalid_kind, payload: { test: "dummy" }, status: "pending").save!
          end
        end
      end

      context "payload" do
        test "validates presence" do
          assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Payload can't be blank") do
            PatreonWebhookEvent.new(kind: 0, status: "pending").save!
          end
        end
      end

      context "status" do
        test "validates presence of status" do
          assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Status can't be blank") do
            PatreonWebhookEvent.new(kind: 0, payload: { test: "dummy" }).save!
          end
        end

        test "validates inclusion of status" do
          assert_raises_with_message(ArgumentError, "'bla bla' is not a valid status") do
            PatreonWebhookEvent.new(kind: 0, payload: { test: "dummy" }, status: "bla bla").save!
          end
        end
      end
    end

    context "#handle" do
      test "increments count on DataDog for specific webhook kind received" do
        webhook_event = create(:patreon_webhook_event, :pending, :members_create)

        VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          assert_predicate webhook_event, :handle
        end

        assert_equal 1, GitHub.dogstats.increments("sponsors.patreon_webhook",
          tags: ["kind:#{webhook_event.kind}"]).count
      end

      test "calls SyncSponsorsPatreonUserJob to sync sponsorships when spu is sponsorable" do
        webhook_event = create(:patreon_webhook_event, :pending, :members_create)
        spu = webhook_event.sponsors_patreon_user
        assert_predicate spu.user, :sponsorable?

        # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser as part of creating
        # the PatreonWebhookEvent test fixture enqueues one:
        travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

        assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [spu, { actor: nil }]) do
          assert_enqueued_with(job: SyncPatreonSponsorshipsJob, args: [spu, { actor: nil }]) do
            VCR.use_cassette("patreon/get_campaigns_and_memberships") do
              assert_predicate webhook_event, :handle
            end
          end
        end
      end

      test "calls SyncSponsorsPatreonUserJob to sync sponsorships for sponsor and sponsorable" do
        sponsorable = create(:user, :sponsorable)
        sponsor_patreon_user = create(:sponsors_patreon_user, :sponsor)
        sponsorable_patreon_user = create(:sponsors_patreon_user, user: sponsorable)
        sponsors_patreon_campaign_webhook = create(:sponsors_patreon_campaign_webhook,
          sponsors_patreon_user: sponsorable_patreon_user)
        webhook_event = create(:patreon_webhook_event, :pending, :members_create,
          sponsors_patreon_user: sponsor_patreon_user,
          sponsors_patreon_campaign_webhook: sponsors_patreon_campaign_webhook)
        refute_predicate webhook_event.sponsors_patreon_user.user, :sponsorable?

        # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
        travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

        assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [sponsorable_patreon_user, { actor: nil }]) do
          assert_enqueued_with(job: SyncSponsorsPatreonUserJob, args: [sponsor_patreon_user, { actor: nil }]) do
            assert_enqueued_with(job: SyncPatreonSponsorshipsJob, args: [sponsorable_patreon_user, { actor: nil }]) do
              VCR.use_cassette("patreon/get_campaigns_and_memberships") do
                assert_predicate webhook_event, :handle
              end
            end
          end
        end
      end

      test "updates status and processed time after processing webhook" do
        spu = create(:sponsors_patreon_user)
        webhook_event = create(:patreon_webhook_event, :pending, :members_create)
        assert_predicate webhook_event, :pending?
        assert_nil webhook_event.processed_at, "webhook must not be processed"

        # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
        travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

        VCR.use_cassette("patreon/get_campaigns_and_memberships") do
          assert_predicate webhook_event, :handle
        end

        assert_predicate webhook_event.reload, :processed?
        refute_nil webhook_event.processed_at
      end

      test "raises UnprocessableError if webhook cannot be marked as processed" do
        spu = create(:sponsors_patreon_user)
        webhook_event = create(:patreon_webhook_event, :pending, :members_create)
        assert_predicate webhook_event, :pending?
        assert_nil webhook_event.processed_at, "webhook event must not be processed"
        expected_error_message = "Could not mark webhook event #{webhook_event.id} as processed: o noes and dang"

        # Wait long enough to allow enqueuing the same job, since creating the SponsorsPatreonUser enqueues one:
        travel_to (SyncSponsorsPatreonUserJob::LOCKOUT_IN_MINUTES + 1).minutes.from_now

        freeze_time
        PatreonWebhookEvent.any_instance.expects(:update).once.with(status: :processed, processed_at: Time.now)
          .returns(false)
        PatreonWebhookEvent.any_instance.stubs(:errors).returns(stub(full_messages: ["o noes", "dang"]))

        assert_raises_with_message(PatreonWebhookEvent::UnprocessableError, expected_error_message) do
          VCR.use_cassette("patreon/get_campaigns_and_memberships") do
            webhook_event.handle
          end
        end

        refute_predicate webhook_event.reload, :processed?
        assert_nil webhook_event.processed_at
      end

      test "ignores webhook if SponsorsPatreonUser is nil" do
        webhook_event = create(:patreon_webhook_event, :pending, :members_create, account_id: nil,
          payload: { "data" => {} })

        result = webhook_event.handle

        assert result
        assert_predicate webhook_event.reload, :ignored?
        refute_nil webhook_event.processed_at
      end

      test "ignores webhook if User is nil" do
        webhook_event = create(:patreon_webhook_event, :pending, :members_create)
        webhook_event.user.delete

        result = webhook_event.reload.handle

        assert result
        assert_predicate webhook_event.reload, :ignored?
        refute_nil webhook_event.processed_at
      end

      test "raises UnprocessableError if User is nil and flagging as 'ignored' fails" do
        webhook_event = create(:patreon_webhook_event, :pending, :members_create)
        webhook_event.user.delete
        expected_error_message = "Could not ignore webhook event ##{webhook_event.id}: o noes and dang"
        fake_errors = stub(full_messages: ["o noes", "dang"])
        freeze_time
        PatreonWebhookEvent.any_instance.expects(:update).once.with(status: :ignored, processed_at: Time.now)
          .returns(false)
        PatreonWebhookEvent.any_instance.stubs(:errors).returns(fake_errors)

        assert_raises_with_message(PatreonWebhookEvent::UnprocessableError, expected_error_message) do
          webhook_event.reload.handle
        end

        refute_predicate webhook_event, :ignored?
        assert_nil webhook_event.processed_at
      end

      test "raises WebhookAlreadyProcessed error if webhook is already processed" do
        webhook_event = create(:patreon_webhook_event, :processed)
        spu = webhook_event.sponsors_patreon_user
        expected_error_message = "Webhook event ##{webhook_event.id} has already been processed"

        assert_raises_with_message(PatreonWebhookEvent::WebhookAlreadyProcessed, expected_error_message) do
          refute_predicate webhook_event, :handle
        end
      end
    end
  else
    test "ignores webhook event when GitHub Sponsors is disabled" do
      webhook_event = create(:patreon_webhook_event, :pending, :members_create)

      result = webhook_event.handle

      assert result
      assert_predicate webhook_event.reload, :ignored?
      refute_nil webhook_event.processed_at
    end
  end

  context ".known_patreon_user?" do
    test "returns true when given the Patreon user ID of a SponsorsPatreonUser" do
      patreon_user = create(:sponsors_patreon_user)
      assert PatreonWebhookEvent.known_patreon_user?(patreon_user.patreon_user_id)
    end

    test "returns false when given a Patreon user ID that does not belong to a SponsorsPatreonUser" do
      refute PatreonWebhookEvent.known_patreon_user?("SomePatreonUserID")
    end
  end
end
