# typed: true
# frozen_string_literal: true

module Codespaces
  class RepositoryAuthorization < ApplicationRecord::Domain::Codespaces
    self.table_name = "codespaces_repository_authorizations"

    belongs_to :user
    belongs_to :repository
  end
end
