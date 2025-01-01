# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  module ICloudEnvironment
    extend T::Sig
    extend T::Helpers
    interface!

    sig { abstract.returns(String) }
    def guid; end

    sig { abstract.returns(String) }
    def state; end

    sig { abstract.returns(T::Boolean) }
    def provisioned?; end
  end
end
