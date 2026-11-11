# typed: strict
# frozen_string_literal: true

class SyncSponsorsPatreonWebhooks
  include GitHub::Memoizer

  class UnprocessableError < StandardError; end

  RECEIVING_URL = T.let("#{GitHub.url}/sponsors/patreon_webhook", String)

  # Public: Subscribes to Patreon webhooks for a Patreon account.
  #
  # inputs - a Hash with the following keys:
  #   :sponsors_patreon_user - a SponsorsPatreonUser
  #
  # Raises a SyncSponsorsPatreonUser::UnprocessableError if something goes wrong.
  sig { params(inputs: T.untyped).returns(T::Array[SponsorsPatreonCampaignWebhook]) }
  def self.call(inputs)
    new(**inputs).call
  end

  sig { params(sponsors_patreon_user: SponsorsPatreonUser).void }
  def initialize(sponsors_patreon_user:)
    @sponsors_patreon_user = sponsors_patreon_user
  end

  sig { returns T::Array[SponsorsPatreonCampaignWebhook] }
  def call
    validate

    delete_sponsors_patreon_webhooks # delete any existing webhooks, in case they're paused
    create_sponsors_patreon_webhooks
  end

  private

  sig { returns(SponsorsPatreonUser) }
  attr_reader :sponsors_patreon_user

  delegate :patreon_client, to: :sponsors_patreon_user

  sig { returns(T::Array[String]) }
  def triggers
    triggers = PatreonWebhookEvent.kinds.keys
    triggers.delete("unknown")

    triggers.map { |trigger| trigger.to_s.gsub(/\_/, ":") }
  end

  sig { void }
  def validate
    raise UnprocessableError.new("GitHub Sponsors is not enabled") unless GitHub.sponsors_enabled?
    raise UnprocessableError.new("Can't authenticate with Patreon API for given account") unless patreon_client
    raise UnprocessableError.new("A Patreon campaign is missing") unless patreon_campaign_ids.present?
  end

  sig { returns T::Set[String] }
  memoize def patreon_campaign_ids
    sponsors_patreon_user.patreon_campaign_ids.to_set
  end

  sig { returns T::Array[SponsorsPatreonCampaignWebhook] }
  def create_sponsors_patreon_webhooks
    patreon_campaign_ids.map { |patreon_campaign_id| create_webhook_on_patreon(patreon_campaign_id) }
  end

  sig { params(patreon_campaign_id: String).returns(SponsorsPatreonCampaignWebhook) }
  def create_webhook_on_patreon(patreon_campaign_id)
    response = begin
      patreon_client.create_webhook(triggers: triggers, campaign_id: patreon_campaign_id, uri: RECEIVING_URL)
    rescue SponsorsPatreonClient::Error => e
      raise UnprocessableError.new("Could not create webhook for SponsorsPatreonUser " \
        "#{sponsors_patreon_user.id} for campaign #{patreon_campaign_id}: #{e.message}")
    end

    webhook = sponsors_patreon_user.sponsors_patreon_campaign_webhooks.new(
      webhook_id: response.dig("data", "id"),
      campaign_id: patreon_campaign_id,
      secret: response.dig("data", "attributes", "secret"),
      triggers: response.dig("data", "attributes", "triggers"),
    )

    unless webhook.save
      error_message = webhook.errors.full_messages.to_sentence
      raise UnprocessableError.new("Could not store Patreon webhook information for SponsorsPatreonUser " \
        "#{sponsors_patreon_user.id} for campaign #{patreon_campaign_id}: #{error_message}")
    end

    webhook
  end

  sig { void }
  def delete_sponsors_patreon_webhooks
    sponsors_patreon_user.clean_up_webhooks_on_patreon
  end
end
