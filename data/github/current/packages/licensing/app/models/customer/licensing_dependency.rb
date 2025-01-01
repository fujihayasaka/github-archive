# typed: strict
# frozen_string_literal: true

module Customer::LicensingDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_many :licensing_model_transitions, class_name: "Licensing::LicensingModelTransition", dependent: :destroy
  end

  sig { params(licensing_model: String, actor: T.nilable(User), transition_date: T.nilable(T.any(Date, String)), ghas_only: T.nilable(T::Boolean), reset_ghas_configuration: T.nilable(T::Boolean)).returns(Licensing::LicensingModelTransition) }
  def new_licensing_model_transition(licensing_model:, actor: User.ghost, transition_date: Date.current, ghas_only: false, reset_ghas_configuration: false)
    ::Licensing::LicensingModelTransition.new(
      customer: self,
      licensing_model: licensing_model,
      transition_date: transition_date,
      status: "scheduled",
      actor: actor,
      reset_ghas_configuration: reset_ghas_configuration,
      ghas_only: ghas_only,
    )
  end

  sig { returns(T::Hash[T::untyped, T::untyped]) }
  def to_licensify_customer_payload
    {
      id: id,
      sdlcLicensingModel: licensify_licensing_model,
      sdlcTrial: !!business&.trial?,
    }
  end

  private

  sig { returns(Integer) }
  def licensify_licensing_model
    if metered_plan?
      return Licensify::Services::V1::LicensingModel::LICENSING_MODEL_METERED
    end

    Licensify::Services::V1::LicensingModel::LICENSING_MODEL_VOLUME
  end
end
