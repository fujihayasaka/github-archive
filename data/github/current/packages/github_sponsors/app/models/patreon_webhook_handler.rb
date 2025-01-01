# typed: strict
# frozen_string_literal: true

class PatreonWebhookHandler
  extend T::Sig
  include ::GitHub::Memoizer

  class InvalidSignature < StandardError; end
  class InvalidTrigger < StandardError; end
  class InvalidPayload < StandardError; end
  class ProcessingError < StandardError; end
  class PatreonUserIdNotFound < InvalidPayload; end
  class PatreonCampaignIdNotFound < InvalidPayload; end
  class WebhookConfigNotFound < InvalidPayload; end
  class PayloadParsingError < InvalidPayload; end

  # Public: Handles webhook requests from Patreon.
  #
  # trigger   - String representing the type of webhook received. See https://docs.patreon.com/#triggers
  # signature - String used to validate the authenticity of the webhook. It is the HEX digest of the message
  #             body HMAC signed (with MD5) using your webhook's secret
  # payload   - String of JSON representing the webhook payload
  #
  # Raises InvalidSignature if webhook signature is invalid.
  sig do
    params(
      trigger: T.nilable(String),
      signature: T.nilable(String),
      payload: T.nilable(String)
    ).returns(PatreonWebhookHandler)
  end
  def self.call(trigger:, signature:, payload:)
    new(trigger: trigger, signature: signature, payload: payload).call
  end

  # Public: Build a Patreon webhook signature.
  #
  # payload - String representing the webhook payload
  # secret - the webhook's secret
  sig { params(payload: T.nilable(String), secret: T.nilable(String)).returns(String) }
  def self.build_signature(payload:, secret:)
    # We disable the GitHub/InsecureHashAlgorithm cop here because the use of MD5 is set by Patreon
    # rubocop:disable GitHub/InsecureHashAlgorithm
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("MD5"), secret, payload)
    # rubocop:enable GitHub/InsecureHashAlgorithm
  end

  sig { params(trigger: T.nilable(String), signature: T.nilable(String), payload: T.nilable(String)).void }
  def initialize(trigger:, signature:, payload:)
    @trigger = trigger
    @signature = signature
    @payload = payload
  end

  # Public: Creates a PatreonWebhookEvent record and calls its #perform method.
  sig { returns PatreonWebhookHandler }
  def call
    return self unless GitHub.sponsors_enabled?

    verify_signature

    # The webhook event is about some Patreon account that is not currently connected with GitHub, so we don't
    # care about it.
    return self unless known_patreon_user?

    webhook_event = ::PatreonWebhookEvent.new(
      account_id: patreon_user_id,
      kind: kind,
      status: :pending,
      payload: parsed_payload,
    )

    unless webhook_event.save
      raise ProcessingError.new("Could not create pending '#{kind}' webhook event for Patreon user ID " \
        "#{patreon_user_id}: #{webhook_event.errors.full_messages.to_sentence}")
    end

    begin
      webhook_event.handle
    rescue ::PatreonWebhookEvent::UnprocessableError, ::PatreonWebhookEvent::WebhookAlreadyProcessed => e
      raise ProcessingError.new(e)
    end

    self
  end

  private

  sig { returns T::Boolean }
  def known_patreon_user?
    PatreonWebhookEvent.known_patreon_user?(patreon_user_id)
  end

  # Private: Verifies the authenticity of the webhook request.
  #
  # Raises InvalidSignature if webhook signature is invalid.
  sig { void }
  def verify_signature
    if SecurityUtils.secure_compare(@signature, expected_signature)
      GitHub.dogstats.increment("#{PatreonWebhookEvent::DATADOG_PREFIX}.verified")
      return
    end

    raise InvalidSignature
  end

  # Private: Build the webhook signature we would expect to receive from Patreon.
  sig { returns(String) }
  def expected_signature
    self.class.build_signature(payload: @payload, secret: webhook_secret)
  end

  sig { returns String }
  memoize def webhook_secret
    raise InvalidTrigger.new("No trigger found") if @trigger.blank?

    secret = ::PatreonWebhookEvent.secret_for(campaign_id: patreon_campaign_id, trigger: @trigger)
    unless secret
      raise WebhookConfigNotFound.new("No webhook config found for Patreon campaign ID " \
        "'#{patreon_campaign_id}' with trigger '#{@trigger}'")
    end

    secret
  end

  sig { returns(String) }
  memoize def kind
    result = ::PatreonWebhookEvent.kind_for_trigger(@trigger || "")
    raise InvalidTrigger.new("Don't know how to handle a webhook with trigger '#{@trigger}'") unless result
    result
  end

  sig { returns String }
  memoize def patreon_campaign_id
    campaign_id = parsed_payload.dig("data", "relationships", "campaign", "data", "id")
    raise PatreonCampaignIdNotFound if campaign_id.to_s.blank?
    Failbot.push(patreon_campaign_id: campaign_id)
    campaign_id
  end

  # Private: Get the Patreon user identifier, failing loudly if we can't find it. Might be the Patreon user ID for
  # the creator (our maintainer or sponsorable) or the patron (our sponsor).
  sig { returns(String) }
  memoize def patreon_user_id
    user_id = parsed_payload.dig("data", "relationships", "user", "data", "id")
    raise PatreonUserIdNotFound if user_id.to_s.blank?
    Failbot.push(patreon_user_id: user_id)
    user_id
  end

  sig { returns(T::Hash[String, T.untyped]) }
  memoize def parsed_payload
    JSON.parse(@payload || "")
  rescue ::JSON::ParserError, ::Yajl::ParseError
    raise PayloadParsingError
  end
end
