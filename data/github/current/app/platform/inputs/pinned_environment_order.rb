# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class PinnedEnvironmentOrder < Platform::Inputs::Base
      description "Ordering options for pinned environments"

      argument :field, Enums::PinnedEnvironmentOrderField, "The field to order pinned environments by.", required: true, visibility: :public
      argument :direction, Enums::OrderDirection, "The direction in which to order pinned environments by the specified field.", required: true, visibility: :public
    end
  end
end
