# typed: strict
# frozen_string_literal: true

# This model is only used for replication for local development
class Language < ApplicationRecord::Domain::Repositories
  belongs_to :language_name
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repositories::IRepository)
end
