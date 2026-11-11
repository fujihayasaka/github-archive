# typed: strict
# frozen_string_literal: true

module SettingsCore
  module ISetting
    extend T::Helpers
    include Kernel

    abstract!

    sig { returns(T.nilable(Targeting::Targetable)) }
    attr_accessor :targetable

    sig { abstract.returns(String) }
    def name; end

    sig { abstract.returns(T.untyped) }
    def value; end

    sig { abstract.returns(T::Array[IRule]) }
    def rules; end

    sig { abstract.returns(String) }
    def provider_name; end

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end
  end
end
