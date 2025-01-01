# typed: true
# frozen_string_literal: true

class RepositoryImport < ApplicationRecord::Domain::Imports

  belongs_to :import
  belongs_to :repository

  validates_presence_of :import, :repository
end
