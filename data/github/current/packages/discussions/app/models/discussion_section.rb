# typed: strict
# frozen_string_literal: true

class DiscussionSection < ApplicationRecord::Domain::Discussions
  include GitHub::Validations

  MAX_SECTIONS_PER_REPO = 25

  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain required: true
  has_many :discussion_categories, dependent: :nullify

  validates :name, presence: true, length: { maximum: 40 }, unicode: true
  validates :emoji, presence: true, unicode: true, single_emoji: true, allowed_emoji: true
  validates :slug, presence: true, uniqueness: { scope: :repository_id }
  validate :does_not_exceed_max_sections_per_repo

  before_validation :strip_name
  before_validation :generate_slug, if: :name_changed?

  # Public: Returns HTML to render the emoji for this section.
  sig { returns(String) }
  def emoji_html
    GitHub::Goomba::SimpleDescriptionPipeline.to_html(emoji, { base_url: GitHub.url }, nil)
  end

  private

  sig { returns(T.nilable(String)) }
  def strip_name
    self.name = name.strip if name.present?
  rescue Encoding::CompatibilityError
  end

  sig { returns(T.nilable(String)) }
  def generate_slug
    # Necessary because this callback runs before the unicode: true validation
    # and .downcase throws an ArgumentError on invalid bytes
    return unless name.valid_encoding?

    self.slug = name.downcase.gsub(/[^\p{Word}]+/, "-").chomp("-")
  end

  sig { void }
  def does_not_exceed_max_sections_per_repo
    existing_sections = self.class.where(repository_id: repository_id).size

    if existing_sections >= MAX_SECTIONS_PER_REPO
      errors.add(:repository, "can only have a maximum of #{MAX_SECTIONS_PER_REPO} sections")
    end
  end
end
