# typed: strict
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class RepositoriesCollab < ApplicationRecord::Collab
      self.abstract_class = true
    end
  end
end
