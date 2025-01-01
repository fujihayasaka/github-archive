# typed: false
# frozen_string_literal: true

class ProfilePin < ApplicationRecord::Domain::Users
  LIMIT_PER_PROFILE = 6

  enum :pinned_item_type, {
    Repository: 0,
    Gist: 1,
  }

  belongs_to :profile
  has_one :user, through: :profile
  belongs_to :pinned_item, polymorphic: true

  after_create :instrument_create
  before_destroy :instrument_destroy

  validates :profile, :pinned_item_type, :pinned_item_id, presence: true
  validates :internal_view, inclusion: { in: [true, false] }
  validates :position, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :profile_other_pins_count, numericality: { less_than: :profile_pin_limit }
  validates :pinned_item_id, uniqueness: { scope: [:pinned_item_type, :profile_id, :internal_view] }
  validate :profile_allowed_for_pin_type
  validate :pinned_item_is_public_in_public_view
  validate :pinned_item_is_not_disabled
  validate :pinned_repo_is_active

  scope :repositories, -> { where(pinned_item_type: pinned_item_types[:Repository]) }

  scope :gists, -> { where(pinned_item_type: pinned_item_types[:Gist]) }

  scope :not_repositories, -> { where.not(pinned_item_type: pinned_item_types[:Repository]) }

  scope :not_gists, -> { where.not(pinned_item_type: pinned_item_types[:Gist]) }

  scope :for_profile, ->(profile_id) { where(profile_id: profile_id) }

  scope :for_repository, ->(repo) { repositories.where(pinned_item_id: repo) }

  scope :for_gist, ->(gist) { gists.where(pinned_item_id: gist) }

  scope :ordered_by_position, -> { order("profile_pins.position ASC") }

  alias_method :repository?, :Repository?
  alias_method :gist?, :Gist?

  def self.hydro_payload(user_or_org, pinned_item_type:, pinned_item_id:, position:, internal_view:)
    payload = { position: position, internal_view: internal_view }

    if pinned_item_type == :Repository
      payload[:repository_id] = pinned_item_id
    elsif pinned_item_type == :Gist
      payload[:gist_id] = pinned_item_id
    end

    if user_or_org.is_a?(Organization)
      payload[:organization] = user_or_org
    elsif user_or_org.is_a?(User)
      payload[:user] = user_or_org
    end

    payload
  end
  private_class_method :hydro_payload

  def self.instrument_create(user_or_org, pinned_item_type:, pinned_item_id:, position:, internal_view:)
    payload = hydro_payload(user_or_org, pinned_item_type: pinned_item_type.to_sym,
                            pinned_item_id: pinned_item_id, position: position, internal_view: internal_view)
    GlobalInstrumenter.instrument("profile_pin.created", payload)
  end

  def self.instrument_delete(user_or_org, pinned_item_type:, pinned_item_id:, position:, internal_view:)
    payload = hydro_payload(user_or_org, pinned_item_type: pinned_item_type.to_sym,
                            pinned_item_id: pinned_item_id, position: position, internal_view: internal_view)
    GlobalInstrumenter.instrument("profile_pin.deleted", payload)
  end

  # Public: Returns the count of pinned items the profile has other than this one.
  def profile_other_pins_count
    return unless profile

    query = profile.profile_pins
    query = query.where("id <> ?", id) if persisted?
    query.count
  end

  private

  def profile_pin_limit
    return 1 unless profile
    LIMIT_PER_PROFILE
  end

  def instrument_create
    self.class.instrument_create(user, pinned_item_type: pinned_item_type,
                                 pinned_item_id: pinned_item_id, position: position, internal_view: internal_view)
  end

  def instrument_destroy
    self.class.instrument_delete(user, pinned_item_type: pinned_item_type,
                                 pinned_item_id: pinned_item_id, position: position, internal_view: internal_view)
  end

  def profile_allowed_for_pin_type
    return unless user && pinned_item_type

    if gist? && !user.user?
      errors.add(:profile, "must belong to a user for pinning a gist")
    elsif !user.user? && !user.organization?
      errors.add(:profile, "must belong to a user or organization")
    end
  end

  def pinned_item_is_public_in_public_view
    return unless pinned_item

    unless pinned_item.public? || internal_view?
      errors.add(:pinned_item, "must be public in public view")
    end
  end

  def pinned_repo_is_active
    return unless repository? && pinned_item

    unless pinned_item.active?
      errors.add(:pinned_item, "must be active")
    end
  end

  def pinned_item_is_not_disabled
    return unless pinned_item

    if pinned_item.disabled_at.present?
      errors.add(:pinned_item, "must not be disabled")
    end
  end
end
