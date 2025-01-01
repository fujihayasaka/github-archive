# typed: false
# frozen_string_literal: true

class Showcase::Item < ApplicationRecord::Domain::Showcases
  include GitHub::UserContent

  self.table_name = "showcase_items"
  # rubocop:todo Rails/InverseOf
  belongs_to :showcase, class_name: "Showcase::Collection", touch: true, foreign_key: :collection_id
  # rubocop:enable Rails/InverseOf
  belongs_to :item, polymorphic: true
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain class_name: "Repository", foreign_key: :item_id
  attr_accessor :name_with_owner

  scope :newest, -> { order("showcase_items.created_at DESC") }

  def self.sorted_by(order)
    case order
    when :stars
      items = order(:id)
      # prefetch repos in domain cache
      Repositories.domain.by_ids(items.map(&:item_id))
      items.sort_by { |item| item.repository.stargazer_count }.reverse
    when :language
      items = order(:id)
      repos = Repositories.domain.by_ids(items.map(&:item_id))
      GitHub::PrefillAssociations.prefill_associations(repos, :primary_language)
      items.sort_by { |item| item.repository.primary_language.name }
    else
      order(:created_at).to_a
    end
  end

  validates_presence_of :item_id
  validates_uniqueness_of :item_id, scope: [:collection_id, :item_id, :item_type], message: "Items can only be added to a collection once."

  def to_s
    item.try(:name_with_owner)
  end

  def primary_language
    item.try(:primary_language)
  end
end
