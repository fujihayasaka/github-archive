# typed: true
# frozen_string_literal: true

class SecurityCampaigns::SecurityCampaign < ApplicationRecord::Domain::SecurityCampaigns
  include Sequence::Context

  include GitHub::RateLimitedCreation

  include Spam::Spammable

  belongs_to :organization
  belongs_to :created_by, class_name: "User"

  has_many :user_managers, class_name: "SecurityCampaigns::SecurityCampaignUserManager", inverse_of: :security_campaign
  destroy_dependents_in_background :user_managers
  has_many :user_manager_users, disable_joins: true, through: :user_managers, source: :user
  has_many :team_managers, class_name: "SecurityCampaigns::SecurityCampaignTeamManager", inverse_of: :security_campaign
  destroy_dependents_in_background :team_managers
  has_many :team_manager_teams, disable_joins: true, through: :team_managers, source: :team
  has_many :security_campaign_issues, class_name: "SecurityCampaigns::SecurityCampaignIssue", inverse_of: :security_campaign
  destroy_dependents_in_background :security_campaign_issues
  has_many :issues, disable_joins: true, through: :security_campaign_issues
  has_many :security_campaign_users, class_name: "SecurityCampaigns::SecurityCampaignUser", inverse_of: :security_campaign
  destroy_dependents_in_background :security_campaign_users

  validate :contact_link_is_valid

  validates :description, presence: true, unless: :draft?
  validates :ends_at, presence: true, unless: :draft?
  validates :closed_at, absence: true, if: :draft?
  validates :creation_query, presence: true, if: :draft?

  validates :organization, presence: true
  validates :name, presence: true, length: { maximum: 50 }
  validates :description, length: { maximum: 255 }
  validates :contact_link, length: { maximum: 2000 }

  before_validation :set_number!, on: :create

  scope :published, -> { where.not(published_at: nil) }
  scope :open, -> { published.where(closed_at: nil) }
  scope :closed, -> { published.where.not(closed_at: nil) }
  scope :draft, -> { where(published_at: nil) }

  enum :alert_type, [:unknown, :code_scanning, :secret_scanning], default: :unknown
  KNOWN_ALERT_TYPES = T.let(SecurityCampaigns::SecurityCampaign.alert_types.except("unknown").keys.map(&:to_s), T::Array[String])
  validates :alert_type, inclusion: { in: KNOWN_ALERT_TYPES, message: "must be specified (cannot be unknown)" }
  scope :for_alert_type, ->(alert_type) { where(alert_type:) }

  setup_spammable(:created_by)

  def sequence_context_type
    self.class.name
  end

  def sequence_context_id
    organization_id
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

  def state
    return :draft if published_at.nil?
    return :closed if !closed_at.nil?
    :open
  end

  def draft?
    state == :draft
  end

  def published?
    !draft?
  end

  def open?
    state == :open
  end

  def closed?
    state == :closed
  end

  sig do
    params(details: SecurityCampaigns::CampaignOpeningDetails, published_at: T.nilable(Time)).
    returns(SecurityCampaigns::SecurityCampaign)
  end
  def self.from_opening_details(details, published_at)
    new(
      organization: details.org,
      name: details.name,
      description: details.description,
      contact_link: details.contact_link,
      user_manager_users: details.managers,
      team_manager_teams: details.team_managers,
      ends_at: details.ends_at,
      creation_query: details.query_string,
      published_at:,
      created_by: details.created_by,
      alert_type: details.alert_type
    )
  end

  private

  def set_number!
    Sequence.create(self) unless Sequence.exists?(self)
    self.number = Sequence.next(self)
  end

  def contact_link_is_valid
    return unless self[:contact_link]

    parsed_url = URI.parse(self[:contact_link])

    unless %w[http https mailto].include?(parsed_url.scheme)
      errors.add(:contact_link, "must use the http, https or mailto scheme")
    end
  rescue URI::Error
    errors.add(:contact_link, "is not a valid contact link")
  end
end
