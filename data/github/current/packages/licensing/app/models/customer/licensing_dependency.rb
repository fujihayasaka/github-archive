# typed: strict
# frozen_string_literal: true

module Customer::LicensingDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_many :licensing_model_transitions, class_name: "Licensing::LicensingModelTransition", dependent: :destroy
  end
end
