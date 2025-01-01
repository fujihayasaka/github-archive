# typed: true
# frozen_string_literal: true

class RepositoryGroupMap < ApplicationRecord::Domain::Repositories
  belongs_to :repository_group
  belongs_to :repository
  validates_presence_of :repository_group, :repository
end
