# typed: strict
# frozen_string_literal: true

class SponsorsPatreonUser < ApplicationRecord::Domain::Sponsors
  include Instrumentation::Model

  belongs_to :user, required: true, inverse_of: :sponsors_patreon_user

  belongs_to :sponsors_listing, primary_key: :sponsorable_id, foreign_key: :user_id, inverse_of: :sponsors_patreon_user
  has_many :sponsors_tiers, through: :sponsors_listing
  has_many :sponsors_patreon_tiers, inverse_of: :sponsors_patreon_user
  has_many :patreon_webhook_events, primary_key: :patreon_user_id, foreign_key: :account_id, dependent: :destroy,
    inverse_of: :sponsors_patreon_user
  has_many :sponsors_patreon_campaign_webhooks, inverse_of: :sponsors_patreon_user, dependent: :destroy

  validates :patreon_user_id, :patreon_email, presence: true
  validates :patreon_user_id, uniqueness: true
  validates :user_id, uniqueness: { scope: :patreon_user_id }
  validate :dupe_patreon_user_has_workaround

  encrypts :patreon_access_token
  encrypts :patreon_refresh_token

  after_create :enqueue_sync_job, :instrument_account_created

  before_destroy :clean_up_sponsorships, :clean_up_webhooks_on_patreon
  after_destroy_commit :instrument_account_destroyed

  scope :for_user, ->(user_or_id) { where(user_id: user_or_id) }
  scope :for_patreon_user, ->(patreon_user_id) { where(patreon_user_id: patreon_user_id) }
  scope :for_patreon_campaign, ->(campaign_id) do
    base_query = left_joins(:sponsors_patreon_campaign_webhooks).left_joins(:sponsors_patreon_tiers)
    base_query.where(sponsors_patreon_campaign_webhooks: { campaign_id: campaign_id })
      .or(base_query.where(sponsors_patreon_tiers: { campaign_id: campaign_id }))
      .distinct
  end

  scope :enabled_as_sponsorable, -> { where(enabled_as_sponsorable: true) }

  # Used for setting the current user when syncing after this record's creation.
  sig { returns(T.nilable(User)) }
  attr_accessor :actor

  delegate :sponsorable_via_patreon?, to: :user

  sig { returns(T.nilable(SponsorsPatreonClient)) }
  def patreon_client
    access_token = patreon_access_token
    refresh_token = patreon_refresh_token
    if access_token.present? && refresh_token.present?
      SponsorsPatreonClient.new(access_token: access_token, refresh_token: refresh_token)
    end
  end

  sig { returns T::Boolean }
  def refresh_tokens_or_destroy
    current_refresh_token = patreon_refresh_token
    return false if current_refresh_token.blank?

    unless user
      destroy!
      return false
    end

    begin
      data = SponsorsPatreonClient.refresh_token(current_refresh_token)
    rescue SponsorsPatreonClient::UnauthorizedError => err
      destroy!
      return false
    end

    access_token = data["access_token"]
    refresh_token = data["refresh_token"]

    if access_token.present? && refresh_token.present?
      update!(patreon_access_token: access_token, patreon_refresh_token: refresh_token)

      expires_in = T.cast(data["expires_in"], Integer)
      enqueue_refresh_tokens_job(expires_in: expires_in)

      return true
    end

    destroy!
    false
  end

  sig { returns T::Boolean }
  def approved_sponsors_listing?
    return false unless GitHub.sponsors_enabled?
    listing = sponsors_listing
    return false unless listing
    listing.approved?
  end

  # Public: The number of days before a Patreon API token is set to expire that we'll try using the refresh token
  # to get updated replacement tokens.
  TOKEN_EXPIRY_GRACE_PERIOD_IN_DAYS = 3

  sig { params(expires_in: Integer).void }
  def enqueue_refresh_tokens_job(expires_in:)
    expires_at = Time.now + expires_in.seconds
    refresh_at = expires_at - TOKEN_EXPIRY_GRACE_PERIOD_IN_DAYS.days
    RefreshSponsorsPatreonTokensJob.set(wait_until: refresh_at).perform_later(self)
  end

  sig { params(identity_result: T::Hash[String, T.untyped]).void }
  def assign_from_identity_response(identity_result)
    self.patreon_user_id = identity_result.dig("data", "id")
    self.patreon_email = identity_result.dig("data", "attributes", "email")
    included_data = identity_result["included"] || []
    campaigns = included_data.select { |data| data["type"] == "campaign" } || []
    published_campaigns = campaigns
      .select { |campaign| campaign.dig("attributes", "published_at").present? }
      .sort_by { |campaign| campaign["attributes"]["published_at"] }
      .reverse
    campaign_with_vanity = published_campaigns.detect { |campaign| campaign.dig("attributes", "vanity").present? }
    self.patreon_username = if campaign_with_vanity
      # Prefer the publicly visible Patreon creator username if they have a published campaign:
      campaign_with_vanity["attributes"]["vanity"]
    else
      identity_result.dig("data", "attributes", "full_name").presence
    end
  end

  sig { returns(T.nilable(String)) }
  def patreon_link
    return nil unless patreon_campaign_ids.any?

    "https://patreon.com/#{patreon_username}"
  end

  sig { returns(T.nilable(String)) }
  def patreon_membership_link
    patreon_url = patreon_link
    return nil unless patreon_url

    # e.g., https://www.patreon.com/anjuan/membership
    patreon_url + "/membership"
  end

  sig { returns(String) }
  def to_s
    id.to_s
  end

  # Public: Is the given amount one that could be used to sponsor this maintainer through Patreon?
  # Checks if the amount is known to exist as a tier on Patreon as well as if it could be represented as a
  # SponsorsTier.
  sig { params(amount_in_cents: Integer).returns(T::Boolean) }
  def valid_patreon_amount?(amount_in_cents)
    return false unless has_patreon_tier_with_value?(amount_in_cents)

    listing = sponsors_listing
    return false unless listing

    listing.amount_meets_required_minimum?(amount_in_cents) ||
      listing.has_published_recurring_tier_with_monthly_price?(amount_in_cents)
  end

  sig { params(amount_in_cents: Integer).returns(T::Boolean) }
  def has_patreon_tier_with_value?(amount_in_cents)
    sponsors_patreon_tiers.with_amount_in_cents(amount_in_cents).exists?
  end

  # Public: Does the user have any Patreon tiers whose amount is allowed by the maintainer for a sponsorship?
  sig { returns(T::Boolean) }
  def any_valid_patreon_tiers?
    valid_patreon_tiers_scope = sponsors_patreon_tiers
    min_custom_tier_amount_in_cents = sponsors_listing&.min_custom_tier_amount_in_cents

    if min_custom_tier_amount_in_cents
      valid_patreon_tiers_scope = valid_patreon_tiers_scope.amount_in_cents_at_least(min_custom_tier_amount_in_cents)
    end

    valid_patreon_tiers_scope.any?
  end

  # Public: Does the maintainer have any Patreon tier whose price does not meet or exceed their minimum custom tier
  # amount setting?
  sig { returns T::Boolean }
  def any_patreon_tiers_not_meeting_maintainer_minimum?
    min_custom_tier_amount_in_cents = sponsors_listing&.min_custom_tier_amount_in_cents

    if min_custom_tier_amount_in_cents
      sponsors_patreon_tiers.amount_in_cents_less_than(min_custom_tier_amount_in_cents).any?
    else
      false # no minimum amount to worry about!
    end
  end

  # Public: The minimum amount in cents among all of user's Patreon tiers
  sig { returns T.nilable(Integer) }
  def min_patreon_tier_amount_in_cents
    sponsors_patreon_tiers.minimum(:amount_in_cents)
  end

  sig { params(include_sponsorships: T.nilable(T::Boolean), delay_in_minutes: Integer).void }
  def sync_sponsors_patreon_user(include_sponsorships: nil, delay_in_minutes: 0)
    if include_sponsorships.nil?
      include_sponsorships = user ? T.must(user).sponsorable? : false
    end
    SyncSponsorsPatreonUserJob.set(wait: delay_in_minutes.minutes).perform_later(self, actor: actor)
    if include_sponsorships
      SyncPatreonSponsorshipsJob.set(wait: delay_in_minutes.minutes).perform_later(self, actor: actor)
    end
  end

  sig { returns T::Array[String] }
  def patreon_campaign_ids
    sponsors_patreon_tiers.distinct.pluck(:campaign_id)
  end

  sig { void }
  def clean_up_sponsorships
    base_query = Sponsorship.active.patreon
    sponsorships = base_query.with_user_or_org_sponsorable(user_id).or(base_query.from_sponsor(user_id))
    actor = user || User.ghost
    sponsorships.each do |sponsorship|
      sponsorship.cancel(actor: actor, reason: :PATREON_ACCOUNT_DISCONNECTED, force: true)
    end
  end

  sig { void }
  def clean_up_webhooks
    patreon_webhook_events.destroy_all

    clean_up_webhooks_on_patreon
  end

  sig { void }
  def clean_up_webhooks_on_patreon
    client = patreon_client
    return unless client

    our_webhook_ids = sponsors_patreon_campaign_webhooks.pluck(:webhook_id).to_set
    sponsors_patreon_campaign_webhooks.destroy_all

    response = begin
      client.get_webhooks
    rescue SponsorsPatreonClient::UnauthorizedError => err
      # Might have been deleting a SponsorsPatreonUser record because we saw its tokens were invalid and we couldn't
      # refresh them.
      # If we can't talk to the Patreon API, we can't delete any of our webhooks there, so nothing more to do.
      return
    end

    webhooks = response["data"]

    webhooks.each do |webhook|
      webhook_id = webhook["id"]
      next if our_webhook_ids.include?(webhook_id) # already deleted

      attributes = webhook["attributes"]
      next unless PatreonWebhookEvent.ours?(uri: attributes["uri"], triggers: attributes["triggers"].to_set)

      client.delete_webhook(webhook_id) # will raise on error
    end
  end

  sig { returns(T::Boolean) }
  def subscribe_to_webhooks?
    return false unless patreon_client

    # Each webhook is created for a particular Patreon campaign, so if we don't have any campaign IDs, we can't
    # create a webhook.
    return false if patreon_campaign_ids.empty?

    !every_campaign_has_a_webhook?
  end

  sig { returns(Symbol) }
  def event_prefix() :sponsors_patreon_user end

  sig { params(prefix: T.any(String, Symbol)).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: event_prefix)
    { "#{prefix}_id".to_sym => id }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    hash = {
      patreon_user_id: patreon_user_id,
      patreon_email: patreon_email,
      patreon_username: patreon_username,
      actor: actor,
    }

    if user.is_a?(Organization)
      hash[:org] = user
    elsif user.is_a?(Business)
      hash[:business] = user
    else
      hash[:user] = user
    end

    hash.merge(event_context)
  end

  private

  sig { void }
  def enqueue_sync_job
    sync_sponsors_patreon_user
  end

  sig { returns T::Boolean }
  def every_campaign_has_a_webhook?
    all_campaign_ids = patreon_campaign_ids.to_set
    campaign_ids_with_webhooks = sponsors_patreon_campaign_webhooks.for_campaign_id(all_campaign_ids)
      .pluck(:campaign_id).to_set
    campaign_ids_without_webhooks = all_campaign_ids - campaign_ids_with_webhooks
    campaign_ids_without_webhooks.empty?
  end

  sig { void }
  def instrument_account_created
    # Audit log
    instrument :sponsors_patreon_user_create, prefix: :sponsors
  end

  sig { void }
  def instrument_account_destroyed
    # Audit log
    instrument :sponsors_patreon_user_destroy, prefix: :sponsors
  end

  sig { void }
  def dupe_patreon_user_has_workaround
    return unless errors.of_kind?(:patreon_user_id, :taken)

    actor_id = GitHub.context[:actor_id]
    return unless actor_id.present?

    actor = User.find_by(id: actor_id)
    return unless actor

    other_github_user = self.class.find_by(patreon_user_id: patreon_user_id)&.user
    return unless other_github_user&.adminable_by?(actor)

    errors.add(:base, "You must disconnect @#{other_github_user.display_login}'s GitHub account from Patreon first")
  end
end
