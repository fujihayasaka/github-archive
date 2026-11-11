# typed: true
# frozen_string_literal: true

class CasMapping < ApplicationRecord::Domain::Users
  include GitHub::Validations
  belongs_to :user
  validates_presence_of :user, :username
  validates_uniqueness_of :username, case_sensitive: false
  validates :username, unicode3: true
end
