# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  module IHadronCloudspace
    extend T::Sig
    extend T::Helpers

    abstract!

    sig { abstract.returns(CloudEnvironments::ICloudEnvironment) }
    def cloud_environment; end

    delegate :provisioned?, to: :cloud_environment
  end
end
