# frozen_string_literal: true

class SuggestedFix < ApplicationRecord
  belongs_to :autofix_suggestion_job
  has_many :suggested_fix_files, inverse_of: :suggested_fix, dependent: :destroy

  enum :review_status, { unreviewed: 0, approved: 1, dismissed: 2 }, prefix: true

  validates :autofix_suggestion_job_id, presence: true, uniqueness: { scope: :autofix_suggestion_job_id }
  validates :review_status, presence: true, inclusion: { in: review_statuses.keys }
end
