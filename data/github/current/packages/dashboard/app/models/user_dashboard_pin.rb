# typed: false
# frozen_string_literal: true

class UserDashboardPin < ApplicationRecord::Collab
  LIMIT_PER_USER_DASHBOARD = 25
  WEB_FEATURE = :dashboard_favorites

  enum :pinned_item_type, {
    Repository: 0,
    Gist: 1,
    Issue: 2,
    Project: 3,
    PullRequest: 4,
    User: 5,
    Organization: 6,
    Team: 7,
  }

  belongs_to :user
  belongs_to :pinned_item, polymorphic: true
  destroy_in_background_with :pinned_item, polymorphic_type_value: pinned_item_types["Repository"]

  after_create :instrument_create
  before_destroy :instrument_destroy

  validates :user, :pinned_item_type, :pinned_item_id, presence: true
  validates :position, presence: true,
            numericality: { only_integer: true, greater_than: 0 }
  validates :user_dashboard_other_pins_count, numericality: { less_than: :user_dashboard_pin_limit }
  validates :pinned_item_id, uniqueness: { scope: [:pinned_item_type, :user_id] }
  validate :pinned_item_is_not_disabled
  validate :pinned_repo_is_active

  scope :pinned_by_user, ->(user_id) { where(user_id: user_id) }

  scope :for_item, ->(item_id, item_type) do
    where(pinned_item_id: item_id, pinned_item_type: item_type)
  end

  scope :ordered_by_position, -> { order("user_dashboard_pins.position ASC") }

  alias_method :repository?, :Repository?
  alias_method :gist?, :Gist?
  alias_method :issue?, :Issue?
  alias_method :project?, :Project?
  alias_method :pull_request?, :PullRequest?
  alias_method :user?, :User?
  alias_method :organization?, :Organization?
  alias_method :team?, :Team?

  def self.instrument_create(user, pinned_item_type:, pinned_item_id:, position:)
    payload = { position: position, user: user, pinned_item_id: pinned_item_id,
                pinned_item_type: pinned_item_type.to_s.underscore.upcase }
    GlobalInstrumenter.instrument("user_dashboard_pin.created", payload)
  end

  def self.instrument_delete(user, pinned_item_type:, pinned_item_id:, position:)
    payload = { position: position, user: user, pinned_item_id: pinned_item_id,
                pinned_item_type: pinned_item_type.to_s.underscore.upcase }
    GlobalInstrumenter.instrument("user_dashboard_pin.deleted", payload)
  end

  # Public: Returns the count of pinned items the profile has other than this one.
  def user_dashboard_other_pins_count
    return unless user

    query = user.dashboard_pins
    query = query.where("id <> ?", id) if persisted?
    query.count
  end

  def pinned_item_global_relay_id
    pinned_item.global_relay_id
  end

  private

  def user_dashboard_pin_limit
    return 1 unless user
    LIMIT_PER_USER_DASHBOARD
  end

  #TODO: Make sure this create/destroy works with profile_pins and user_dashboard_pins
  def instrument_create
    self.class.instrument_create(user, pinned_item_type: pinned_item_type,
                                 pinned_item_id: pinned_item_id, position: position)
  end

  def instrument_destroy
    self.class.instrument_delete(user, pinned_item_type: pinned_item_type,
                                 pinned_item_id: pinned_item_id, position: position)
  end

  def pinned_repo_is_active
    return unless repository? && pinned_item

    unless pinned_item.active?
      errors.add(:pinned_item, "must be active")
    end
  end

  def pinned_item_is_not_disabled
    return unless pinned_item
    return unless pinned_item_type == "Repository" || pinned_item_type == "Gist"

    if pinned_item.disabled_at.present?
      errors.add(:pinned_item, "must not be disabled")
    end
  end
end
