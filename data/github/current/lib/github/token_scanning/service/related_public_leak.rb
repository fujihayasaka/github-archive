# typed: strict
# frozen_string_literal: true

# Wrapper class for the protobuf RelatedPublicLeak class returned from the service.
#
class GitHub::TokenScanning::Service::RelatedPublicLeak < T::Struct
  const :repository_id, Integer
  const :location, GitHub::Proto::SecretScanning::Api::V2::TokenLocation
end
