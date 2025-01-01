# typed: true
# frozen_string_literal: true

class MemexProjectColumn::Settings::ProgressConfiguration
  include ActiveModel::Validations

  attr_reader :color,
              :hide_numerals,
              :variant

  ALLOWED_COLORS = MemexProjectColumn::Settings::ALLOWED_COLORS
  VARIANTS = %w(SOLID SEGMENTED RING).freeze

  validates :color, inclusion: { in: ALLOWED_COLORS, message: "is not one of #{ALLOWED_COLORS}" }, allow_nil: true
  validates :hide_numerals, inclusion: { in: [true, false], message: "is not a boolean" }, allow_nil: true
  validates :variant, inclusion: { in: VARIANTS, message: "is not one of #{VARIANTS}" }, allow_nil: true

  def initialize(config)
    @color = config[:color]
    @hide_numerals = config[:hide_numerals]
    @variant = config[:variant]
  end

  def serialize
    return @serialized if defined?(@serialized)

    @serialized = {
      color: @color,
      hide_numerals: @hide_numerals,
      variant: @variant,
    }.compact
  end
end
