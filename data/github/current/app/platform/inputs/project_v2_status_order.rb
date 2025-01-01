# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ProjectV2StatusOrder < Platform::Inputs::Base
      description "Ways in which project v2 status updates can be ordered."

      argument :field, Enums::ProjectV2StatusUpdateOrderField, "The field by which to order nodes.", required: true
      argument :direction, Enums::OrderDirection, "The direction in which to order nodes.", required: true
    end
  end
end
