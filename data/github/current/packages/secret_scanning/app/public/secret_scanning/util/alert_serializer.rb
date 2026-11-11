# typed: strict
# frozen_string_literal: true

# A temporary migration area to add Sorbet types for methods in Api::Serializer::SecretScanningAlertDependency
# so that we remove "dependency" style code and don't make an untyped method call to those methods via a symbol.
# The serializer dependency is large and has lots of dependencies, so slowly moving 1 method at a time is less painful.
#
# Ideally, domain models should be responsible for their own serialization, like in the case with
# the `SecretScanning::Models::PatternConfigurations::PatternConfiguration#serialize_api` method.
# But the alerts API doesn't use our modern domain models currently. So this serialization util will have to do.
class SecretScanning::Util::AlertSerializer
  sig { params(alert: T.nilable(GitHub::TokenScanning::Service::Token)).returns(String) }
  def self.validity_name(alert)
    validity = alert&.validity
    case validity
    when :TOKEN_VALIDITY_UNKNOWN
      "unknown"
    when :TOKEN_VALIDITY_ACTIVE
      "active"
    when :TOKEN_VALIDITY_INACTIVE, :TOKEN_VALIDITY_REVOKED
      "inactive" # consolidate revoked with inactive
    else
      "unknown" # consolidate unverifiable with unknown
    end
  end
end
