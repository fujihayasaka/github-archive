# typed: strict
# frozen_string_literal: true

class InternalRepository < ApplicationRecord::Domain::Repositories
  belongs_to :repository
  belongs_to :business

  validates_presence_of :repository_id
  validates_uniqueness_of :repository_id
  validates_presence_of :business_id
end
