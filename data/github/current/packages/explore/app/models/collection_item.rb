# typed: true
# frozen_string_literal: true

class CollectionItem < ApplicationRecord::Ballast # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  belongs_to :content, polymorphic: true
  belongs_to :collection, class_name: "ExploreCollection", foreign_key: :collection_id,
    inverse_of: :items

  CONTENT_TYPE_REPOSITORY = "Repository"
  CONTENT_TYPES = [
    "CollectionUrl",
    "CollectionVideo",
    CONTENT_TYPE_REPOSITORY,
    "Organization",
    "User",
  ].freeze

  validates :content_type, inclusion: { in: CONTENT_TYPES }
  validates :content, presence: true
  validates :collection, presence: true

  def repository?
    content_type == CONTENT_TYPE_REPOSITORY
  end

  def self.visible
    select do |item|
      if item.content_type.in?(%w(Repository Organization User))
        content = item.content
        content.present? && !content.spammy? && content.public?
      else
        true
      end
    end
  end
end
