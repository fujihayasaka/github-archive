# typed: true
# frozen_string_literal: true

class SavedReply < ApplicationRecord::Domain::Users
  include GitHub::Relay::GlobalIdentification
  include GitHub::UTF8
  include GitHub::Validations

  validates_presence_of :user_id, :title, :body
  validates :body, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT },
    unicode: true, allow_blank: true, allow_nil: true
  validates :title, bytesize: { maximum: 1024 }, allow_blank: false,
    allow_nil: false
  validate  :reply_count_limit, on: :create

  MAX_REPLIES_PER_USER = 100

  belongs_to :user

  extend GitHub::Encoding
  force_utf8_encoding :title, :body

  def title=(value)
    self[:title] = value.to_s if value
  end

  def reply_count_limit
    if T.must(user).saved_replies.count >= MAX_REPLIES_PER_USER
      errors.add :reply_count, "contains too many replies"
    end
  end

  # Public: Whether a saved reply is user generated vs internally generated
  #
  # Returns true if saved reply is internally generated
  def default?
    !persisted?
  end
end
