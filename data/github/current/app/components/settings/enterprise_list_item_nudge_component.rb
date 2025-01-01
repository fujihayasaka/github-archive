# typed: strict
# frozen_string_literal: true

module Settings
  class EnterpriseListItemNudgeComponent < EnterpriseListItemComponent
    include DigitalFrontDoor::NudgeConcern


    sig { returns(Integer) }
    attr_reader :variant

    sig { returns(Symbol) }
    attr_reader :render_variant

    sig { returns(T.nilable(Symbol)) }
    attr_reader :render_nudge_type

    sig do
      params(
        business: Business,
        user: User,
        show_trial_information: T::Boolean,
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(business:, user:, show_trial_information: false, **system_arguments)
      super(**T.unsafe({ business: business, user: user, show_trial_information: show_trial_information, **system_arguments }))

      @variant = T.let(get_dfd_new_tasks_variant(user), Integer)

      variant_map = {
        0 => :variant_show_no_experience,
        1 => :variant_show_treatment_1,
      }

      @render_variant = T.let(variant_map[@variant] || :variant_show_no_experience, Symbol)


      # ordered by priority
      nudge_types = [:cb, :org, :repo, :code, :ghas]
      @render_nudge_type = T.let(
        nudge_types.find { |type| show_dfd_new_tasks_nudge?(user, business, type) },
      T.nilable(Symbol))
    end

  end

end
