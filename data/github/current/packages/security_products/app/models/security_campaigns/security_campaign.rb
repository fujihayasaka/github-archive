# typed: true
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaign < ApplicationRecord::Domain::SecurityCampaigns
  extend T::Sig

  include Sequence::Context

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

  scope :for_repo_with_alerts, -> (repo) {
    where(organization_id: repo.owner_id).
    where(
      SecurityCampaigns::SecurityCampaignAlert.
      where(arel_table[:id].eq(SecurityCampaigns::SecurityCampaignAlert.arel_table[:security_campaign_id])).
      where(repository_id: repo.id).arel.exists
    )
  }

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

  def open?
    closed_at.nil?
  end

  def closed?
    !closed_at.nil?
  end

  private

  def set_number!
    Sequence.create(self) unless Sequence.exists?(self)
    self.number = Sequence.next(self)
  end
end
