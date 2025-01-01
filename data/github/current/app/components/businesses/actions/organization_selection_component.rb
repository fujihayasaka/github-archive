# typed: true
# frozen_string_literal: true

module Businesses
  module Actions
    class OrganizationSelectionComponent < ApplicationComponent
      def initialize(business:, organizations:, selected_organizations: [], policy_type:, policy_id: "", input_classes: [])
        @business = business
        @organizations = organizations
        @selected_organizations = selected_organizations
        @policy_type = policy_type
        @policy_id = policy_id
        @input_classes = input_classes
      end

      def aria_id_prefix
        return @policy_type unless @policy_id.present?
        "#{@policy_type}-#{@policy_id}"
      end
    end
  end
end
