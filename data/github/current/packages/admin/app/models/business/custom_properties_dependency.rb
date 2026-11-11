# typed: strict
# frozen_string_literal: true

module Business::CustomPropertiesDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Business }

  sig { void }
  def destroy_custom_properties_for_orgs
    T.bind(self, Business)
    Orgs.domain.custom_properties.destroy_all_property_definitions(self)
  end
end
