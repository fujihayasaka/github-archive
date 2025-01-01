# typed: strict
# frozen_string_literal: true

module Stafftools
  class BulkDmcaTakedownRepository < ApplicationRecord::Collab
    belongs_to :repository, class_name: "::Repository"
    belongs_to :bulk_dmca_takedown, class_name: "Stafftools::BulkDmcaTakedown"
  end
end
