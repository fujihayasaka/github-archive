# typed: strict
# frozen_string_literal: true

class InternalRepository < ApplicationRecord::Domain::Repositories
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :business

  validates_presence_of :repository_id
  validates_uniqueness_of :repository_id
  validates_presence_of :business_id

  after_commit(on: [:update, :destroy, :create]) do # rubocop:disable GitHub/AvoidActiveRecordCallbacks
    next unless GH::Context.enabled?

    T.bind(self, InternalRepository)
    Repositories.domain.cache.dirty_id(repository_id)
  end
end
