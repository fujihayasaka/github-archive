# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IntegrationFeatureState < Platform::Enums::Base
      graphql_name "IntegrationFeatureState"
      description "Track the state of this feature if it should be visible and or filterable."
      visibility :internal

      value "DRAFT", "Default state. Feature is being built but shouldn't be visible or filterable."
      value "VISIBLE", "Feature will display on IntegrationListing pages."
      value "FILTERABLE", "Feature will display on IntegrationListing pages and will also appear within the filtering bar."
      value "HIDDEN", "Feature is hidden for changes or temporary problems."
    end
  end
end
