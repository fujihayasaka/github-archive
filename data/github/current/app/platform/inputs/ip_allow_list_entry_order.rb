# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class IpAllowListEntryOrder < Platform::Inputs::Base
      description "Ordering options for IP allow list entry connections."

      argument :field, Enums::IpAllowListEntryOrderField, "The field to order IP allow list entries by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
