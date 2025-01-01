# typed: true
# frozen_string_literal: true

class StacksPolicy::AllowedStacksPattern < ApplicationRecord::Collab # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  self.table_name = "allowed_stacks_patterns"

  # rubocop:todo Rails/InverseOf
  belongs_to :stacksallowlist, foreign_key: :stacks_allowlist_id, class_name: "StacksPolicy::StacksAllowlist"
  # rubocop:enable Rails/InverseOf

  validates :value, presence: true, length: { maximum: 255 }

  # For patterns we allow exact match (ignore case) + usage of the * wildcard.
  def regex
    escaped = Regexp.escape(value).gsub("\\*", ".*")
    Regexp.new "\\A#{escaped}\\z", Regexp::IGNORECASE
  end
end
