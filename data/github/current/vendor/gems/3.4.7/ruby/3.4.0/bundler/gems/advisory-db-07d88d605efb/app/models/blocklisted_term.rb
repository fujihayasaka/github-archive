# frozen_string_literal: true

class BlocklistedTerm < ApplicationRecord
  LEVELS = ["warn", "remove"].freeze
  TYPES = ["content", "cna", "cpe"].freeze
  REGEXP_PARTS = %r{\A/(?<content>.+)/(?<ignorecase>i)?\z}

  has_many :matches, class_name: "BlocklistMatch", dependent: :delete_all
  has_many :advisory_reviews, through: :matches

  validates :pattern, presence: true
  validate :regexp_must_be_valid, if: :pattern?
  validates :level, inclusion: { in: LEVELS }
  validates :term_type, inclusion: { in: TYPES }

  scope :removes_from_curation, -> { where(level: "remove") }

  delegate :match?, to: :regexp

  def regexp
    # We memoize based on the pattern here so that if the pattern changes, as
    # would happen when we update a blocklisted term, we're validating the new
    # regular expression, not a stale, memoized regular expression based on the
    # previous pattern.
    @regexp ||= {}
    return @regexp.fetch(pattern) if @regexp.key?(pattern)

    parts = REGEXP_PARTS.match(pattern)
    if parts
      content = parts[:content]
      options = parts[:ignorecase] ? Regexp::IGNORECASE : 0
    else
      content = Regexp.escape(pattern)
      options = 0
    end

    # Wrap the regular expression content with a non-capturing group to:
    # - Match a non-word character (basically anything that is not alphanumeric)
    # - Match the start or end of the string (\A or \z)
    content.prepend('(?:\W|\A)').concat('(?:\W|\z)')

    @regexp[pattern] = Regexp.new(content, options)
  end

  private

  def regexp_must_be_valid
    regexp
  rescue RegexpError
    errors.add(:pattern)
  end
end
