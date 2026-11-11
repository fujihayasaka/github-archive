# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class UserNameDisplayConfiguration < Platform::Enums::Base
      visibility :internal
      description "The possible user name display configurations."

      value "HANDLE", "Only show GitHub handle", value: "handle"
      value "NAME_AND_HANDLE", "Show profile name and handle", value: "name_handle"
    end
  end
end
