# typed: strict
# frozen_string_literal: true

class SponsorsListingStafftoolsMetadata < ApplicationRecord::Domain::Sponsors
  extend T::Sig

  NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS = 60

  belongs_to :sponsors_listing, required: true
  belongs_to :banned_by, class_name: "User", foreign_key: "banned_by_id" # rubocop:todo Rails/InverseOf
  belongs_to :sponsorable, required: true, class_name: "User", inverse_of: :sponsors_listing_stafftools_metadata

  belongs_to :sponsorable_profile, class_name: "Profile", primary_key: "user_id", foreign_key: "sponsorable_id",
    inverse_of: :sponsors_listing_stafftools_metadata

  has_many :sponsorable_received_abuse_reports, class_name: "AbuseReport", foreign_key: "reported_user_id",
    primary_key: "sponsorable_id", inverse_of: :reported_user_sponsors_listing_stafftools_metadata

  has_many :sponsorable_non_fork_public_repositories, -> do
    T.bind(self, T.untyped)
    public_scope.active.where(parent_id: nil)
  end, foreign_key: "owner_id", primary_key: "sponsorable_id", class_name: "Repository",
    inverse_of: :owner_sponsors_listing_stafftools_metadata

  before_validation :set_sponsorable, on: :create
  before_validation :set_sponsorable_created_at, on: :create

  before_create :set_sponsorable_time_zone_name
  before_create :set_has_received_abuse_report
  before_create :set_has_customized_user_profile
  before_create :set_has_public_non_fork_repository

  validates :sponsorable_id, uniqueness: true
  validates :sponsors_listing_id, uniqueness: true
  validates :sponsorable_created_at, presence: true
  validate :sponsorable_created_at_matches_sponsorable

  # Public: Fetch Sponsors metadata by github accounts created from 60 days ago
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :newly_created_sponsorables, -> { where(sponsorable_created_at: NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS.days.ago..) }

  # Public: Fetch Sponsors metadata for accounts who have not customized their public GitHub user profile pages.
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :uncustomized_github_profile, -> { where(has_customized_user_profile: false) }

  # Public: Fetch Sponsors metadata for accounts whose time zone we don't know.
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :without_time_zone, -> { where(sponsorable_time_zone_name: nil).or(where(sponsorable_time_zone_name: "")) }

  # Public: Fetch Sponsors metadata for accounts who do not have any public repositories that aren't forks.
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :without_public_non_fork_repository, -> { where(has_public_non_fork_repository: false) }

  scope :with_time_zone, -> do
    where.not(sponsorable_time_zone_name: nil).where.not(sponsorable_time_zone_name: "")
  end

  # Public: Fetch Sponsors metadata for accounts who have a time zone that's not in one of our Sponsors-supported
  # countries.
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :unsupported_time_zone, -> do
    supported_time_zone_names = Sponsors::TimeZone.supported_names
    with_time_zone.where.not(sponsorable_time_zone_name: supported_time_zone_names)
  end

  # Public: Fetch Sponsors metadata for accounts that have a time zone existing within the specified country, or
  # accounts that have no time zone when no country is specified.
  #
  # country_code - a 2-character country code as a String, e.g., "CA" for "Canada", or nil
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :with_time_zone_matching_country, ->(country_code) do
    if country_code.present?
      time_zones_for_country = Sponsors::TimeZone.names(country_code: country_code)
      if time_zones_for_country.any?
        where(sponsorable_time_zone_name: time_zones_for_country)
      else
        none
      end
    else
      without_time_zone
    end
  end

  # Public: Sort Sponsors metadata by when the sponsorable signed up for GitHub, or when the sponsorable organization
  # was created.
  #
  # direction - :asc or :desc
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :ordered_by_user_creation_time, ->(direction) do
    direction = :desc unless %i(asc desc).include?(direction)
    order(sponsorable_created_at: direction)
  end

  # Public: Sort metadata records by when the maintainer requested approval for their Sponsors profile.
  #
  # direction - :asc or :desc
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :ordered_by_approval_requested_at, ->(direction) do
    direction = :desc unless %i(asc desc).include?(direction)
    order(approval_requested_at: direction)
  end

  # Public: Sort metadata records by when the state of the maintainer's Sponsors profile last changed.
  #
  # direction - :asc or :desc
  #
  # Returns an ActiveRecord::Relation of SponsorsListingStafftoolsMetadata.
  scope :ordered_by_reviewed_at, ->(direction) do
    direction = :desc unless %i(asc desc).include?(direction)
    order(reviewed_at: direction)
  end

  scope :ignored, -> { where(ignored: true) }
  scope :not_ignored, -> { where(ignored: false) }

  PROFILE_CUSTOMIZATION_FIELDS = T.let([:name, :bio, :twitter_username, :blog, :company].freeze, T::Array[Symbol])

  sig { params(profile: T.nilable(Profile)).returns(T::Boolean) }
  def self.profile_customized_for_sponsors?(profile)
    return false unless profile

    profile_fields = PROFILE_CUSTOMIZATION_FIELDS.map do |field|
      case field
      when :name then profile.name
      when :bio then profile.bio
      when :twitter_username then profile.twitter_username
      when :blog then profile.blog
      when :company then profile.company
      end
    end
    profile_fields.any?(&:present?)
  end

  # Public: Will the given changes have the potential to affect a stafftools metadata record's
  # `has_customized_user_profile` value?
  #
  # changes - a Hash of changes that were made to a Profile record, of the format:
  #           Hash[String] => [old_value, new_value];
  #           e.g., `{"bio"=>["I have customized my profile", nil]}`
  sig { params(changes: T::Hash[String, T::Array[T.nilable(String)]]).returns(T::Boolean) }
  def self.profile_changes_can_affect_has_customized_user_profile?(changes)
    relevant_changed_values = changes.select { |field, _| PROFILE_CUSTOMIZATION_FIELDS.include?(field.to_sym) }.values
    return false if relevant_changed_values.empty?

    relevant_changed_values.any? { |old_value, new_value| old_value.blank? && new_value.present? } ||
      relevant_changed_values.all? { |old_value, new_value| old_value.present? && new_value.blank? }
  end

  # Public: Figure out the timestamp that a Sponsors listing most recently transitioned to the given state.
  #
  # state - a Symbol representing the state of the Sponsors listing; valid values include :draft, :banned,
  #         :waitlisted, :approved, :spammy, :sdn_disabled, :pending_approval, :disabled
  sig { params(state: Symbol).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def in_current_state_since(state)
    return approval_requested_at if :pending_approval == state
    return banned_at if :banned == state
    reviewed_at
  end

  sig { returns(T::Boolean) }
  def reviewed?
    reviewed_at.present?
  end

  sig { returns(T::Boolean) }
  def recently_created_github_account?
    sponsorable_created_at >= NEW_ACCOUNT_AGE_CUTOFF_IN_DAYS.days.ago
  end

  private

  sig { void }
  def sponsorable_created_at_matches_sponsorable
    return unless self[:sponsorable_created_at] && sponsorable

    unless sponsorable_created_at == T.must(sponsorable).created_at
      errors.add(:sponsorable_created_at, "doesn't match the sponsorable's creation time " \
        "for #{sponsorable}")
    end
  end

  sig { void }
  def set_sponsorable
    return unless sponsors_listing
    self.sponsorable = T.must(sponsors_listing).sponsorable
  end

  sig { void }
  def set_sponsorable_created_at
    return unless sponsorable
    value = T.must(sponsorable).created_at
    return unless value
    self.sponsorable_created_at = value
  end

  sig { void }
  def set_sponsorable_time_zone_name
    return unless sponsorable
    self.sponsorable_time_zone_name = T.must(sponsorable).time_zone_name
  end

  sig { void }
  def set_has_received_abuse_report
    self.has_received_abuse_report = sponsorable_received_abuse_reports.any?
  end

  sig { void }
  def set_has_customized_user_profile
    self.has_customized_user_profile = self.class.profile_customized_for_sponsors?(sponsorable_profile)
  end

  sig { void }
  def set_has_public_non_fork_repository
    self.has_public_non_fork_repository = sponsorable_non_fork_public_repositories.any?
  end
end
