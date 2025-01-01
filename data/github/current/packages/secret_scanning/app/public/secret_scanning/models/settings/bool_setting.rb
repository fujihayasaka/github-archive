# typed: strict
# frozen_string_literal: true

module SecretScanning::Models::Settings
  class BoolSetting < T::Enum
    enums do
      NotSet = new("not-set")
      Disabled = new("disabled")
      Enabled = new("enabled")
    end

    sig { params(proto: T.any(Symbol, Integer)).returns(BoolSetting) }
    def self.from_proto(proto)
      case proto
      when :NOT_SET, 0
        BoolSetting::NotSet
      when :DISABLED, 1
        BoolSetting::Disabled
      when :ENABLED, 2
        BoolSetting::Enabled
      else
        BoolSetting::NotSet
      end
    end

    sig { returns(Symbol) }
    def to_proto
      case self
      when BoolSetting::NotSet
        :NOT_SET
      when BoolSetting::Disabled
        :DISABLED
      when BoolSetting::Enabled
        :ENABLED
      else
        T.absurd(self)
      end
    end
  end
end
