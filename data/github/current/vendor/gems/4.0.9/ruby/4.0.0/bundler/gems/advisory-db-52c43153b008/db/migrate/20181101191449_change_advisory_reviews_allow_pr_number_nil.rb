# frozen_string_literal: true

class ChangeAdvisoryReviewsAllowPRNumberNil < ActiveRecord::Migration[5.2]
  def change
    change_column_null :advisory_reviews, :pull_request_number, true
  end
end
