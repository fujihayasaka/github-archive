# frozen_string_literal: true

class ReferencePayload
  URL_PATTERN = %r{\Ahttps?://.+} # Yes, this could be better!

  include ActiveModel::Validations

  validates :url, class: String,
    format: { with: URL_PATTERN, allow_blank: true }

  with_options on: :publication do
    validates :url, presence: true
  end

  attr_reader :url

  def initialize(url)
    @url = url
  end
end
