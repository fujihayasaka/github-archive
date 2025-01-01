# typed: strict
# frozen_string_literal: true

module Stafftools
  class BulkDmcaTakedownRepository < ApplicationRecord::Collab
    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain class_name: "::Repository"
    belongs_to :bulk_dmca_takedown, class_name: "Stafftools::BulkDmcaTakedown"
  end
end
