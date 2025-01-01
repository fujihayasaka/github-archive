# typed: strict
# frozen_string_literal: true

Money.locale_backend = :i18n
Money.disallow_currency_conversion!
Money.rounding_mode = BigDecimal::ROUND_HALF_EVEN
