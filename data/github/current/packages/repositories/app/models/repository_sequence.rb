# typed: strict
# frozen_string_literal: true

class RepositorySequence < ApplicationRecord::Domain::Repositories
  belongs_to :repository
end
