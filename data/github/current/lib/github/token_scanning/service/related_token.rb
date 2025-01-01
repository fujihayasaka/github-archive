# typed: strict
# frozen_string_literal: true

# Wrapper class for the protobuf RelatedToken class returned from the service.
#
class GitHub::TokenScanning::Service::RelatedToken < T::Struct
  const :repository_id, Integer
  const :number, Integer
  const :token_type, String
end
