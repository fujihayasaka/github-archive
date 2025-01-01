# typed: true
# frozen_string_literal: true

module SecurityCenter
  class SubheadComponent < ApplicationComponent
    extend T::Sig

    renders_one :phase_label, -> do
      SecurityCenter::PhaseComponent.new(@phase, ml: 1)
    end

    renders_one :feedback_link, -> do
      SecurityCenter::FeedbackLinkComponent.new(
        @phase,
        actor: @actor,
        scope: @scope,
        font_size: :small,
        vertical_align: :middle,
      )
    end

    sig do
      params(
        actor: User,
        scope: T.any(Repository, Organization, Business),
        heading: String,
        subheading: T.nilable(String),
        phase: Symbol,
        hide_border: T::Boolean,
      ).void
    end
    def initialize(actor:, scope:, heading:, subheading: nil, phase: :ga, hide_border: false)
      raise ArgumentError, "`heading` cannot be empty" if heading.blank?

      @actor = actor
      @scope = scope
      @heading = heading
      @subheading = subheading
      @phase = phase
      @hide_border = hide_border
    end
  end
end
