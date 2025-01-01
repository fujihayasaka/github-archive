# frozen_string_literal: true

class Label < ApplicationRecord
  COLOR_REGEXP = /\A[0-9a-f]{6}\z/iu # e.g., ff00ff
  COLOR_SHORTHAND_REGEXP = /\A[0-9a-f]{3}\z/iu # e.g., fff
  DESCRIPTION_MAX_LENGTH = 100
  NAME_MAX_LENGTH = 50
  NAME_REGEXP = /\A[^,]*\Z/iu

  has_many :advisory_reviews_labels, dependent: :delete_all
  has_many :advisory_reviews, through: :advisory_reviews_labels

  serialize :label_settings, coder: LabelSettings

  validates :name, length: { maximum: NAME_MAX_LENGTH }, format: NAME_REGEXP, presence: true, uniqueness: { case_sensitive: false }
  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, allow_blank: true
  validates :color, format: COLOR_REGEXP

  before_validation :normalize_text_fields, :expand_color_shorthand

  scope :with_name_like, lambda { |query|
    next all if query.blank?

    sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)
    where("name LIKE ?", "%#{sanitized_query}%")
  }

  def color
    read_attribute(:color) || "ededed"
  end

  private

  # Strip leading/trailing whitespaces,
  # and replace newlines with spaces.
  def normalize_text_fields
    self.name = name.tr("\n", " ").strip if name
    self.description = description.tr("\n", " ").strip if description
  end

  # Expands colors of three character length `"666"`
  # into six character hex code `"666666"`.
  def expand_color_shorthand
    self.color = [color[0] * 2, color[1] * 2, color[2] * 2].join if color.match?(COLOR_SHORTHAND_REGEXP)
  end
end
