# frozen_string_literal: true

class BlocklistMatch < ApplicationRecord
  belongs_to :blocklisted_term
  belongs_to :advisory_review
end
