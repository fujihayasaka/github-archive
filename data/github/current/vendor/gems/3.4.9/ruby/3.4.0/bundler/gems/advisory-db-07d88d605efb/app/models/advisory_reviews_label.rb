# frozen_string_literal: true

class AdvisoryReviewsLabel < ApplicationRecord
  belongs_to :advisory_review
  belongs_to :label
end
