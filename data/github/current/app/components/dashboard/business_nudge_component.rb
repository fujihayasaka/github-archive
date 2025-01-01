# typed: strict
# frozen_string_literal: true

module Dashboard
  class BusinessNudgeComponent < ApplicationComponent
    include ApplicationComponent::Rescuable
    include DigitalFrontDoor::NudgeConcern

    rescue_from StandardError, with: :nothing

    sig { returns(Integer) }
    attr_reader :variant

    sig { returns(Symbol) }
    attr_reader :render_variant

    sig { returns(T.nilable(Symbol)) }
    attr_reader :render_nudge_type

    sig { returns T.nilable(User) }
    attr_reader :user

    sig { returns T.nilable(Business) }
    attr_reader :business

    sig do
      params(
        business: Business,
        user: User,
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(business:, user:, **system_arguments)
      @business = business
      @user = user

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

    sig { returns T::Boolean }
    def render?
      return false if @user.nil?
      return false if @render_nudge_type.nil?
      return false if @business.suspended?
      true
    end

  end

end
