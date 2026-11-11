# typed: true
# frozen_string_literal: true

module Codespaces
  class RepositoryAuthorization < ApplicationRecord::Domain::Codespaces
    self.table_name = "codespaces_repository_authorizations"

    belongs_to :user
    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain
  end
end
