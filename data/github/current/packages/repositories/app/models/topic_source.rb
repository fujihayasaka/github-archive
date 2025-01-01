# typed: true
# frozen_string_literal: true


class TopicSource < ApplicationRecord::Domain::UsersBallast
  belongs_to :source, polymorphic: true
  belongs_to :topic, inverse_of: :sources

  CONTENT_TYPES = %w[
    Repository
    User
  ]

  validates :source_type, inclusion: { in: CONTENT_TYPES }
  validates :source, presence: true
  validates :topic, presence: true
end
