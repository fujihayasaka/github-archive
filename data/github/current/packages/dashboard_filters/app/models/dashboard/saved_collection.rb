# typed: true
# frozen_string_literal: true

class Dashboard::SavedCollection < ApplicationRecord::Collab
  self.table_name = :saved_collections

  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification
  include SearchDisplayable

  PROTECTED_TYPES = {
    reviews: 0,
  }.freeze

  enum :protected_type, PROTECTED_TYPES, suffix: true

  validates :dashboard, presence: true

  belongs_to :dashboard,
    class_name: "UserDashboard",
    foreign_key: :dashboard_id,
    inverse_of: :saved_collections

  has_many :saved_views,
    class_name: "Dashboard::SavedView",
    inverse_of: :saved_collection,
    dependent: :destroy

  validates :priority, uniqueness: { scope: :dashboard_id, allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true
    }

  validates :protected_type, uniqueness: { scope: :dashboard_id, allow_nil: true }

  after_create_commit :instrument_create
  after_commit :instrument_edit, on: :update
  before_destroy :instrument_destroy

  delegate :user, to: :dashboard

  def platform_type_name
    "SavedCollection"
  end

  def async_saved_views(order_by: {})
    order_by_field = order_by.dig(:field) || "created_at"
    order_by_direction = order_by.dig(:direction) || "DESC"
    Promise.resolve(saved_views.order("saved_views.#{order_by_field} #{order_by_direction}"))
  end

  private

  def instrument_create
    GlobalInstrumenter.instrument("dashboard_saved_collection.create", {
      user: user,
      dashboard_saved_collection: self
    })
  end

  def instrument_edit
    GlobalInstrumenter.instrument("dashboard_saved_collection.update", {
      user: user,
      dashboard_saved_collection: self
    })
  end

  def instrument_destroy
    GlobalInstrumenter.instrument("dashboard_saved_collection.destroy", {
      user: user,
      dashboard_saved_collection: self
    })
  end
end
