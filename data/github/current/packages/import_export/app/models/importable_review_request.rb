# typed: true
# frozen_string_literal: true

class ImportableReviewRequest < ReviewRequest
  include Importable

  def type
    "ReviewRequest"
  end
end
