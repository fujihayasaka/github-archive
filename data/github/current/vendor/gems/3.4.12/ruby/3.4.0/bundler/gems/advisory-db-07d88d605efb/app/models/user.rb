# frozen_string_literal: true

class User < ApplicationRecord
  validates :login, presence: true

  has_many :advisory_review_approvals

  def color_mode
    self[:color_mode] || "auto"
  end

  def avatar_url
    "https://github.com/#{login}.png"
  end

  def email
    "#{login}@github.com"
  end
end
