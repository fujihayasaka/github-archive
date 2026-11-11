# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class Math

    sig { params(value: Numeric, total: Numeric, floor: T::Boolean).returns(Integer) }
    def self.to_percent_int(value, total, floor: false)
      # Resolve total to 1 to prevent divide by 0
      val = (value.to_f / (total == 0 ? 1 : total)) * 100
      if floor
        val.floor
      else
        val.round.to_i
      end
    end
  end
end
