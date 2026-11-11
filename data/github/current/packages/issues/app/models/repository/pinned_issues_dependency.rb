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

    validate :validate_pinned_issue_count
  end

  def validate_pinned_issue_count
    if FeatureFlag.vexi.enabled?("read_from_replicas_validate_pinned_issues", default: false)
      ActiveRecord::Base.connected_to(role: :reading) do
        if pinned_issues.size > PINNED_ISSUES_LIMIT
          errors.add(:pinned_issues, :too_long, count: PINNED_ISSUES_LIMIT)
        end
      end
    else
      if pinned_issues.size > PINNED_ISSUES_LIMIT
        errors.add(:pinned_issues, :too_long, count: PINNED_ISSUES_LIMIT)
      end
    end
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
