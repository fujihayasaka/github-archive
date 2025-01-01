# typed: true
# frozen_string_literal: true

# Public: Represents the webhooks we create for GitHub Sponsors maintainers on Patreon.
class SponsorsPatreonCampaignWebhook < ApplicationRecord::Domain::Sponsors
  belongs_to :sponsors_patreon_user, required: true, inverse_of: :sponsors_patreon_campaign_webhooks

  belongs_to :sponsors_patreon_tier, foreign_key: :campaign_id, primary_key: :campaign_id,
    inverse_of: :sponsors_patreon_campaign_webhook

  validates :campaign_id, presence: true, uniqueness: { scope: :sponsors_patreon_user_id }
  validates :webhook_id, presence: true, uniqueness: true
  validates :triggers, presence: true
  validates :secret, presence: true

  serialize :triggers, type: Array

  encrypts :secret

  before_destroy :delete_webhook_on_patreon

  scope :for_campaign_id, ->(campaign_id) { where(campaign_id: campaign_id) }
  scope :for_webhook_id, ->(webhook_id) { where(webhook_id: webhook_id) }
  scope :for_patreon_user_id, ->(patreon_user_id) do
    joins(:sponsors_patreon_user).merge(SponsorsPatreonUser.for_patreon_user(patreon_user_id))
  end

  private

  sig { returns T.nilable(SponsorsPatreonClient) }
  def patreon_client
    sponsors_patreon_user&.patreon_client
  end

  sig { void }
  def delete_webhook_on_patreon
    patreon_client&.delete_webhook(webhook_id) if webhook_id.present?
  end
end
