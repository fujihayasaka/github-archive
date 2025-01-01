# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AuthenticationFlaggedReason < Platform::Enums::Base
      description "A reason why a particular authentication was flagged as unexpected."
      graphql_name "AuthenticationFlaggedReason"
      visibility :internal

      value "UNRECOGNIZED_LOCATION", "The login came from an unknown country code", value: "unrecognized_location"
      value "UNRECOGNIZED_DEVICE", "The login came from an unknown device", value: "unrecognized_device"
      value "UNRECOGNIZED_DEVICE_AND_LOCATION", "The login came from an unknown device and unknown country code", value: "unrecognized_device_and_location"
      value "NO_RECORDS_EXIST", "There are no records for this user", value: "no_records_exist"
    end
  end
end
