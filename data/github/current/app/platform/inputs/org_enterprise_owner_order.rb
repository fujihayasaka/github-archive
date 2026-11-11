# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class OrgEnterpriseOwnerOrder < Platform::Inputs::Base
      docs_category :orgs
      description "Ordering options for an organization's enterprise owner connections."

      argument :field, Enums::OrgEnterpriseOwnerOrderField, "The field to order enterprise owners by.", required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
