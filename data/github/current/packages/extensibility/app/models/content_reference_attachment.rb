# typed: true
# frozen_string_literal: true

class ContentReferenceAttachment < ApplicationRecord::Ballast

  # Use VARBINARY limit from the database
  TITLE_BYTESIZE_LIMIT = 1024

  include Workflow
  include GitHub::Validations
  include GitHub::UserContent

  belongs_to :content_reference
  belongs_to :integration

  extend GitHub::Encoding
  force_utf8_encoding :title, :body

  workflow :state do
    state :pending, 0 do
      event :processed, transitions_to: :processed
    end

    state :processed, 10 do
      event :hidden, transitions_to: :hidden
    end

    state :hidden, 20
  end

  delegate :content, :repository, to: :content_reference

  validates_presence_of :title, message: "cannot be blank"
  validates_presence_of :body, message: "cannot be blank"
  validates_presence_of :integration
  validates_presence_of :content_reference
  validates_uniqueness_of :integration, scope: :content_reference, message: "can only have one attachment per content reference"
  validates :title, bytesize: { maximum: TITLE_BYTESIZE_LIMIT }, unicode: true
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT },
            allow_blank: true, allow_nil: true
  validate :content_reference_cannot_be_too_old

  after_save :refresh_body_html

  def self.for_integration_id(integration_id)
    where(integration_id: integration_id)
  end

  def refresh_body_html
    # no-op while this feature is removed
  end

  def content_reference_cannot_be_too_old
    if T.must(T.must(content_reference).created_at) < 6.hours.ago
      errors.add(:content_reference, "is older than 6 hours")
    end
  end

  def platform_type_name
    "ContentAttachment"
  end
end
