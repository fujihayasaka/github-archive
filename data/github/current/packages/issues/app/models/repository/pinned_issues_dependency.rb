# typed: true
# frozen_string_literal: true
# actions-specific functionality for repositories
module Repository::PinnedIssuesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { Repository }

  PINNED_ISSUES_LIMIT = 3

  included do
    T.bind(self, T.class_of(Repository))

    has_many :pinned_issues,
      -> { order("sort ASC") },
      dependent: :destroy

    validates :pinned_issues, length: { maximum: PINNED_ISSUES_LIMIT }
  end

  def async_can_pin_issues?(user)
    resources.issues.async_writable_by?(user)
  end

  def can_pin_issues?(user)
    async_can_pin_issues?(user).sync
  end

  def reorder_pinned_issues(ordered_issue_ids)
    pinned_issues.each do |pin|
      position = ordered_issue_ids.index(pin.issue_id) + 1 # 1-based index
      pin.update_attribute(:sort, position)
    end
  end
end
