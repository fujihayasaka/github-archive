# typed: true
# frozen_string_literal: true

class Dashboard::SavedView < ApplicationRecord::Collab
  self.table_name = :saved_views

  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::Relay::GlobalIdentification
  include SearchDisplayable

  MAX_PER_COLLECTION = 25

  # relationships
  belongs_to :saved_collection,
    class_name: "Dashboard::SavedCollection",
    inverse_of: :saved_views

  # validations
  validates :saved_collection_id, presence: true
  validates :query, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true
  validates :priority, uniqueness: { scope: :saved_collection_id, allow_nil: true },
    numericality: {
      less_than_or_equal_to: GitHub::Prioritizable::MAX_PRIORITY_VALUE,
      greater_than_or_equal_to: 0,
      allow_nil: true
    }
  validate :collection_has_less_than_max_views, on: :create

  # attributes
  attribute :compressed_query, CompressedBinary.new(self.name, "query")
  alias_attribute :query, :compressed_query

  after_create_commit :instrument_create
  after_commit :instrument_update, on: :update
  before_destroy :instrument_destroy

  delegate :user, to: :saved_collection

  def compressed_query
    utf8(read_attribute(:compressed_query))
  end
  alias_method :query, :compressed_query

  def async_dashboard
    async_saved_collection.then do |saved_collection|
      saved_collection.async_dashboard
    end
  end

  private

  def collection_has_less_than_max_views
    if self.class.where(saved_collection_id: saved_collection_id).count >= MAX_PER_COLLECTION
      errors.add(:base, "cannot have more than #{MAX_PER_COLLECTION} saved views")
    end
  end

  def instrument_create
    GlobalInstrumenter.instrument("dashboard_saved_view.create", {
      user: user,
      dashboard_saved_view: self,
      dashboard_saved_collection: saved_collection,
    })
  end

  def instrument_update
    GlobalInstrumenter.instrument("dashboard_saved_view.update", {
      user: user,
      dashboard_saved_view: self,
      dashboard_saved_collection: saved_collection,
    })
  end

  def instrument_destroy
    GlobalInstrumenter.instrument("dashboard_saved_view.destroy", {
      user: user,
      dashboard_saved_view: self,
      dashboard_saved_collection: saved_collection,
    })
  end
end
