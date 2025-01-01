# typed: true
# frozen_string_literal: true

class Import < ApplicationRecord::Domain::Imports
  belongs_to :creator, class_name: "User", foreign_key: "user_id" # rubocop:todo Rails/InverseOf

  has_many :repository_imports
  has_many :repositories, through: :repository_imports, disable_joins: true

  has_many :pull_request_imports
  has_many :pull_requests, through: :pull_request_imports, disable_joins: true

  validates_presence_of :creator
end
