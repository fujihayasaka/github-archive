# typed: true
# frozen_string_literal: true

require "test_helper"

class PatreonWebhookHandlerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::SponsorsPatreonTestHelpers

  fixtures do
    @sponsorable_patreon_user = create(:sponsors_patreon_user)
    @patreon_tier = create(:sponsors_patreon_tier, sponsors_patreon_user: @sponsorable_patreon_user,
      campaign_id: "10596612")
    @webhook = create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: @sponsorable_patreon_user,
      campaign_id: @patreon_tier.campaign_id)
    @sponsor_patreon_user = create(:sponsors_patreon_user, :sponsor)
  end

  setup do
    @valid_payload = valid_payload(patreon_user_id: @sponsor_patreon_user.patreon_user_id,
      campaign_id: @patreon_tier.campaign_id)
    @datadog_prefix = PatreonWebhookEvent::DATADOG_PREFIX
  end

  if GitHub.sponsors_enabled?
    context ".call" do
      test "creates a PatreonWebhookEvent when the payload involves a user connected with Patreon" do
        signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: @webhook.secret)

        assert_difference(-> { GitHub.dogstats.increments("#{@datadog_prefix}.verified").size }) do
          VCR.use_cassette("patreon/get_campaigns_and_memberships") do
            assert_difference(-> { PatreonWebhookEvent.count }, 1) do
              PatreonWebhookHandler.call(trigger: "members:create", signature: signature, payload: @valid_payload)
            end
          end
        end

        patreon_webhook = PatreonWebhookEvent.last
        assert_predicate patreon_webhook, :processed?
        refute_nil T.must(patreon_webhook).processed_at
        assert_equal "members_create", T.must(patreon_webhook).kind
        assert_instance_of ActiveSupport::HashWithIndifferentAccess, patreon_webhook.payload
        assert_equal "10596612", patreon_webhook.payload.dig("data", "relationships", "campaign", "data", "id")
        assert_equal @sponsor_patreon_user.patreon_user_id,
          patreon_webhook.payload.dig("data", "relationships", "user", "data", "id")
        assert_equal @sponsor_patreon_user.patreon_user_id, T.must(patreon_webhook).account_id
        assert_equal @sponsor_patreon_user, T.must(patreon_webhook).sponsors_patreon_user
      end

      test "does not create a PatreonWebhookEvent when the payload involves a user not connected with Patreon" do
        payload = valid_payload(patreon_user_id: "PatronNotConnectedOnGitHub", campaign_id: @patreon_tier.campaign_id)
        signature = PatreonWebhookHandler.build_signature(payload: payload, secret: @webhook.secret)

        assert_difference(-> { GitHub.dogstats.increments("#{@datadog_prefix}.verified").size }) do
          VCR.use_cassette("patreon/get_campaigns_and_memberships") do
            assert_no_difference(-> { PatreonWebhookEvent.count }) do
              PatreonWebhookHandler.call(trigger: "members:create", signature: signature, payload: payload)
            end
          end
        end
      end

      test "raises ProcessingError when creating the webhook event fails" do
        PatreonWebhookEvent.any_instance.expects(:save).once.returns(false)
        errors = ActiveModel::Errors.new(PatreonWebhookEvent.new)
        errors.add(:base, "o noes")
        PatreonWebhookEvent.any_instance.stubs(:errors).returns(errors)
        signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: @webhook.secret)

        error = assert_raises(PatreonWebhookHandler::ProcessingError) do
          PatreonWebhookHandler.call(trigger: "members:update", signature: signature, payload: @valid_payload)
        end

        assert_equal "Could not create pending 'members_update' webhook event for Patreon user ID " \
          "#{@sponsor_patreon_user.patreon_user_id}: o noes", error.message
      end

      test "raises PatreonUserIdNotFound when no user ID is found in payload" do
        payload = valid_payload(patreon_user_id: "", campaign_id: @patreon_tier.campaign_id)
        signature = PatreonWebhookHandler.build_signature(payload: payload, secret: @webhook.secret)

        assert_raises PatreonWebhookHandler::PatreonUserIdNotFound do
          PatreonWebhookHandler.call(trigger: @webhook.triggers.first, signature: signature, payload: payload)
        end
      end

      test "raises WebhookConfigNotFound when trigger is not included in webhook triggers" do
        signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: @webhook.secret)

        error = assert_raises(PatreonWebhookHandler::WebhookConfigNotFound) do
          PatreonWebhookHandler.call(trigger: "bad_trigger", signature: signature, payload: @valid_payload)
        end

        assert_equal "No webhook config found for Patreon campaign ID '#{@patreon_tier.campaign_id}' with " \
          "trigger 'bad_trigger'", error.message
      end

      test "raises InvalidTrigger when we don't have a 'kind' mapping for it" do
        trigger = "some:other:trigger"
        @webhook.update!(triggers: [trigger])
        signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: @webhook.secret)

        error = assert_raises(PatreonWebhookHandler::InvalidTrigger) do
          PatreonWebhookHandler.call(trigger: trigger, signature: signature, payload: @valid_payload)
        end

        assert_equal "Don't know how to handle a webhook with trigger '#{trigger}'", error.message
      end

      test "raises InvalidSignature when signature is invalid" do
        assert_no_difference(-> { GitHub.dogstats.increments("#{@datadog_prefix}.verified").size }) do
          assert_raises PatreonWebhookHandler::InvalidSignature do
            PatreonWebhookHandler.call(trigger: @webhook.triggers.first, signature: "invalid_signature",
              payload: @valid_payload)
          end
        end
      end

      test "raises WebhookConfigNotFound when no webhook is found for that campaign" do
        signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: @webhook.secret)
        trigger = @webhook.triggers.first
        @webhook.delete

        assert_no_difference(-> { GitHub.dogstats.increments("#{@datadog_prefix}.verified").size }) do
          error = assert_raises(PatreonWebhookHandler::WebhookConfigNotFound) do
            PatreonWebhookHandler.call(trigger: trigger, signature: signature, payload: @valid_payload)
          end

          assert_equal "No webhook config found for Patreon campaign ID '#{@patreon_tier.campaign_id}' with " \
            "trigger '#{trigger}'", error.message
        end
      end

      test "raises PayloadParsingError when payload is invalid" do
        payload = "not a json"
        signature = PatreonWebhookHandler.build_signature(payload: payload, secret: @webhook.secret)

        assert_raises PatreonWebhookHandler::PayloadParsingError do
          PatreonWebhookHandler.call(trigger: @webhook.triggers.first, signature: signature, payload: payload)
        end
      end
    end

    context ".build_signature" do
      test "uses MD5 and the Patreon webhook secret to sign the payload" do
        secret = @webhook.secret
        # rubocop:disable GitHub/InsecureHashAlgorithm
        expected_signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("MD5"), secret, @valid_payload)
        # rubocop:enable GitHub/InsecureHashAlgorithm

        actual_signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: secret)

        assert_equal expected_signature, actual_signature
      end
    end
  else
    test "no-op when GitHub Sponsors is disabled" do
      signature = PatreonWebhookHandler.build_signature(payload: @valid_payload, secret: @webhook.secret)

      assert_no_difference(-> { PatreonWebhookEvent.count }) do
        PatreonWebhookHandler.call(trigger: @webhook.triggers.first, signature: signature, payload: @valid_payload)
      end
    end
  end
end
