# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  CloudEnvironment = ::Codespace
  CloudEnvironment.include(CloudEnvironments::ICloudEnvironment)
end
