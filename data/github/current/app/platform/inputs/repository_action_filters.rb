# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RepositoryActionFilters < Platform::Inputs::Base
      description "Filtering options for repository action connections."
      visibility :internal

      argument :featured, Enums::RepositoryActionFeaturedState, "Select actions based on whether they are featured or not.", required: false
      argument :name, String, "The name of the repository action to match.", required: false
      argument :owner, String, "Select repository actions based on the name of their owner.", required: false
      argument :category, String, "The slug of the Marketplace category to match.", required: false
      argument :state, Enums::RepositoryActionState, "Select actions based on their state.", required: false
    end
  end
end
