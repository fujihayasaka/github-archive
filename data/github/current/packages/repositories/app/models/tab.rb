# typed: true
# frozen_string_literal: true

class Tab < ApplicationRecord::Domain::Repositories
  include GitHub::Validations
  belongs_to :repository
  destroy_in_background_with :repository

  validates_presence_of :anchor, :url
  validates :anchor, unicode3: true
  validate :url_protocol_allowed

  def url_protocol_allowed
    return if url.blank?
    uri = Addressable::URI.parse(url)
    return errors.add(:url, "must be absolute") unless uri.absolute?
    errors.add(:url, "uses an invalid protocol") unless %w[http https].include? uri.scheme
  rescue Addressable::URI::InvalidURIError
    errors.add(:url, "is invalid")
  end
end
