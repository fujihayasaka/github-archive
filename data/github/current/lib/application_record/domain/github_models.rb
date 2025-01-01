# typed: true
# frozen_string_literal: true

module ApplicationRecord
  module Domain
    class GitHubModels < ApplicationRecord::GitHubModels
      self.abstract_class = true
    end
  end
end
