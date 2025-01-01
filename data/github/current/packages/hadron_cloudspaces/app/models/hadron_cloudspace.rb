# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

class HadronCloudspace
  extend T::Sig
  extend T::Helpers
  include HadronCloudspaces::IHadronCloudspace

  sig { override.returns(CloudEnvironments::ICloudEnvironment) }
  attr_reader :cloud_environment

  sig { params(cloud_environment: CloudEnvironments::ICloudEnvironment).void }
  def initialize(cloud_environment)
    @cloud_environment = cloud_environment
  end
end
