# typed: strict
# frozen_string_literal: true

class RepositoryAuthVersion < ApplicationRecord::Domain::Repositories
  belongs_to :repository
end
