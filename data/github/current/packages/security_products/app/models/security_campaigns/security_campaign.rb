# typed: true
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaign < ApplicationRecord::Domain::SecurityCampaigns
  include Sequence::Context

  include GitHub::RateLimitedCreation

  belongs_to :organization
  belongs_to :manager, class_name: "User"

  has_many :security_campaign_alerts
  has_many :security_campaign_repositories

  validates :organization, presence: true
  validates :name, presence: true, length: { maximum: 50 }
  validates :description, presence: true, length: { maximum: 255 }
  validates :ends_at, presence: true
  validates :manager, presence: true

  before_validation :set_number!, on: :create

  ## Deprecated and will be removed when new data model is shipped
  ## Use SecurityCampaigns::CampaignWithCounts.for_repo_with_alerts instead
  scope :for_repo_with_alerts, -> (repo) {
    where(organization_id: repo.owner_id).
    where(
      SecurityCampaigns::SecurityCampaignAlert.
      where(arel_table[:id].eq(SecurityCampaigns::SecurityCampaignAlert.arel_table[:security_campaign_id])).
      where(repository_id: repo.id).arel.exists
    )
  }

  ## Deprecated and will be removed when new data model is shipped
  ## Use SecurityCampaigns::CampaignWithCounts.for_repo_and_alert_number instead
  scope :for_repo_and_alert_number, -> (repo, number) {
    where(organization_id: repo.owner_id).
    where(
      SecurityCampaigns::SecurityCampaignAlert.
      where(arel_table[:id].eq(SecurityCampaigns::SecurityCampaignAlert.arel_table[:security_campaign_id])).
      where(repository_id: repo.id, logical_alert_number: number).arel.exists
    )
  }

  scope :open, -> { where(closed_at: nil) }

  scope :closed, -> { where.not(closed_at: nil) }

  def sequence_context_type
    self.class.name
  end

  def sequence_context_id
    organization_id
  end

  # Skip incrementing the tries count for the content creation rate limit if
  # the feature flag is not enabled.
  #
  # Overrides the method included from GitHub::RateLimitedCreation
  def check_creation_rate_limit
    if organization&.feature_enabled?(:security_campaigns_rate_limited_creation)
      super
    else
      super(skip_increment: true)
    end
  end

  # user in this case refers to the organization of the campaign (i.e. `user_for_rate_limited_creation`)
  LIMITS = T.let({
    user_minute:          10,
    user_hour:            500,
  }.freeze, T::Hash[Symbol, Integer])

  def creation_rate_limit_configuration
    LIMITS
  end

  # Ensure the creation_rate_limit_configuration is used
  def apply_dynamic_rate_limit_configuration?
    true
  end

  def user_for_rate_limited_creation
    organization
  end

  def open?
    closed_at.nil?
  end

  def closed?
    !closed_at.nil?
  end

  # Fallback on the ghost user when the original manager has been deleted.
  sig { returns(User) }
  def safe_manager
    manager || User.ghost
  end

  private

  def set_number!
    Sequence.create(self) unless Sequence.exists?(self)
    self.number = Sequence.next(self)
  end
end
