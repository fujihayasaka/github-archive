# typed: true
# frozen_string_literal: true

# A label that belongs to a user / organization.
class UserLabel < ApplicationRecord::Collab
  include Instrumentation::Model
  include Labelable

  attribute :name, StringFromBinary.new
  attribute :lowercase_name, StringFromBinary.new
  attribute :description, StringFromBinary.new

  validates :name, length: { maximum: NAME_MAX_LENGTH }, presence: true, format: NAME_REGEXP

  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, allow_blank: true

  belongs_to :user, required: true

  before_validation :normalize_name, :normalize_description, :expand_color_shorthand,
                    :set_lowercase_name

  validate :uniqueness_of_name
  validate :name_has_more_than_emoji
  validate :owned_by_organization
  validates_format_of     :color, with: COLOR_REGEXP

  after_commit :instrument_update, on: :update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destruction, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_creation, on: :create # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def label_attributes
    attributes.with_indifferent_access.slice(:name, :description, :color)
  end

  def event_prefix
    if user.is_a?(Organization)
      :organization_default_label
    else
      :user_default_label
    end
  end

  def event_context(prefix: event_prefix)
    {
      prefix => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def event_payload
    payload = { event_prefix => self }

    if user.is_a?(Organization)
      payload[:org] = user
    else
      payload[:user] = user
    end

    payload
  end

  def instrument_creation
    instrument :create
  end

  def instrument_update
    return unless previous_changes.present?

    changes = {
      "#{event_prefix}_was" => previous_changes["name"]&.first,
      "#{event_prefix}_description_was" => previous_changes["description"]&.first,
    }
    instrument :update, changes
  end

  def instrument_destruction
    instrument :destroy
  end

  private

  def owner
    user
  end

  def sibling_labels_with_same_name
    UserLabel.where(user: user).where(lowercase_name: lowercase_name)
  end

  def owned_by_organization
    return unless user = self.user

    unless user.organization?
      errors.add(:user, "must be an organization user")
    end
  end
end
