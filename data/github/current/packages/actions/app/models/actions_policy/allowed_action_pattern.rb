# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class ActionsPolicy::AllowedActionPattern < ApplicationRecord::Collab
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  self.table_name = "allowed_action_patterns"

  # rubocop:todo Rails/InverseOf
  belongs_to :allowlist, foreign_key: :actions_allowlist_id, class_name: "ActionsPolicy::Allowlist"
  # rubocop:enable Rails/InverseOf

  validates :value, presence: true, length: { maximum: 255 }

  scope :allowed, -> { where("value NOT LIKE ?", "#{BLOCKED_PREFIX}%") }
  scope :blocked, -> { where("value LIKE ?", "#{BLOCKED_PREFIX}%") }

  BLOCKED_PREFIX = "!"

  # For patterns we allow exact match (ignore case) + usage of the * wildcard.
  def regex(trim_blocked_prefix: false)
    pattern = if trim_blocked_prefix
      value.delete_prefix(BLOCKED_PREFIX)
    else
      value
    end

    escaped = Regexp.escape(pattern).gsub("\\*", ".*")
    Regexp.new "\\A#{escaped}\\z", Regexp::IGNORECASE
  end
end
