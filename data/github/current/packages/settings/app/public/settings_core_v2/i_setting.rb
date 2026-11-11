# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  module ISetting
    extend T::Helpers
    include Kernel

    abstract!

    sig { abstract.returns(T.untyped) }
    def resource; end

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.untyped) }
    def value; end

    sig { abstract.returns(T::Array[IRule]) }
    def rules; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { returns(T::Hash[String, T.untyped]) }
    def serialize
      {
        "id" => id,
        "name" => name,
        "value" => value,
        "rules" => rules.sort_by(&:priority).map { |rule| rule.serialize },
      }
    end
  end
end
