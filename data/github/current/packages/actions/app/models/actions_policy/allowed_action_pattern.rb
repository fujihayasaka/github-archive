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

  # For patterns we allow exact match (ignore case) + usage of the * wildcard.
  def regex
    escaped = Regexp.escape(value).gsub("\\*", ".*")
    Regexp.new "\\A#{escaped}\\z", Regexp::IGNORECASE
  end
end
