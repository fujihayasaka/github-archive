# typed: strict
# frozen_string_literal: true

# Public: Represents an event triggered by a webhook on Patreon. We would have created the webhook on Patreon
# originally.
class PatreonWebhookEvent < ApplicationRecord::Ballast
  extend T::Sig

  DATADOG_PREFIX = "sponsors.patreon_webhook"

  self.table_name = "patreon_webhooks"

  class UnprocessableError < StandardError; end
  class WebhookAlreadyProcessed < StandardError; end

  enum :kind, {
    unknown: 0,
    # Members
    members_create: 1,
    members_update: 2,
    members_delete: 3,
    # Pledges
    members_pledge_create: 4,
    members_pledge_update: 5,
    members_pledge_delete: 6,
  }

  enum :status, {
    pending: "pending",
    processed: "processed",
    ignored: "ignored",
  }

  belongs_to :sponsors_patreon_user, primary_key: :patreon_user_id, foreign_key: :account_id,
    inverse_of: :patreon_webhook_events

  has_one :user, through: :sponsors_patreon_user, disable_joins: true

  validates :kind, presence: true, on: :create
  validates :status, presence: true, on: :create
  validates :payload, presence: true, on: :create

  store :payload, coder: JSON

  sig { params(kind: T.any(String, Symbol)).returns(T.nilable(String)) }
  def self.trigger_for_kind(kind)
    return nil if kind.to_s == "unknown"
    kind.to_s.gsub(/\_/, ":") # e.g., "members_create" => "members:create"
  end

  sig { returns(T::Array[String]) }
  def self.triggers
    kinds.keys.map { |kind| trigger_for_kind(kind) }.compact
  end

  sig { params(trigger: String).returns(T.nilable(String)) }
  def self.kind_for_trigger(trigger)
    kind = trigger.gsub(/\:/, "_") # e.g., "members:create" => "members_create"
    kind if kinds[kind]
  end

  sig { params(uri: String, triggers: T::Set[String]).returns(T::Boolean) }
  def self.ours?(uri:, triggers:)
    SyncSponsorsPatreonWebhooks::RECEIVING_URL == uri && self.triggers.to_set == triggers
  end

  # Public: Get the secret for a webhook that's identified by its Patreon campaign ID and trigger.
  sig { params(campaign_id: String, trigger: String).returns(T.nilable(String)) }
  def self.secret_for(campaign_id:, trigger:)
    webhooks = SponsorsPatreonCampaignWebhook.for_campaign_id(campaign_id)
      .limit(2) # only need one, but want to know if more than one has the campaign ID
      .order(id: :desc) # newest first
      .to_a
    GitHub.dogstats.increment("#{DATADOG_PREFIX}.multiple_webhooks_for_campaign") if webhooks.size > 1
    webhook = webhooks.first
    webhook.secret if webhook && webhook.triggers.include?(trigger)
  end

  # Public: Is the given Patreon user ID associated with a GitHub user?
  sig { params(patreon_user_id: String).returns(T::Boolean) }
  def self.known_patreon_user?(patreon_user_id)
    SponsorsPatreonUser.for_patreon_user(patreon_user_id).exists?
  end

  # Public: Do any necessary processing based on the Patreon webhook event payload.
  sig { returns(T::Boolean) }
  def handle
    spu = sponsors_patreon_user
    Failbot.push(user_id: spu.user_id, patreon_user_id: spu.patreon_user_id) if spu
    Failbot.push(user: T.must(user).display_login, sponsorable: T.must(user).sponsorable?) if user

    raise WebhookAlreadyProcessed.new("Webhook event ##{id} has already been processed") if processed?

    if ignore?
      unless update(status: :ignored, processed_at: Time.now)
        raise UnprocessableError.new("Could not ignore webhook event ##{id}: #{errors.full_messages.to_sentence}")
      end
      return true
    end

    GitHub.dogstats.increment(DATADOG_PREFIX, tags: ["kind:#{kind}"])

    spu&.sync_sponsors_patreon_user # sponsor
    sponsorable_patreon_user&.sync_sponsors_patreon_user # sponsorable

    unless update(status: :processed, processed_at: Time.now)
      error_message = errors.full_messages.to_sentence
      raise UnprocessableError.new("Could not mark webhook event #{id} as processed: #{error_message}")
    end

    true
  end

  private

  sig { returns T::Boolean }
  def ignore?
    !GitHub.sponsors_enabled? || sponsors_patreon_user.nil? || user.nil?
  end

  sig { returns T.nilable(String) }
  def patreon_campaign_id
    payload&.dig("data", "relationships", "campaign", "data", "id")
  end

  sig { returns T.nilable(SponsorsPatreonUser) }
  def sponsorable_patreon_user
    campaign_id = patreon_campaign_id
    return if campaign_id.blank?
    SponsorsPatreonUser.for_patreon_campaign(campaign_id).first
  end
end
