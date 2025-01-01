# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SponsorshipPrivacy < Platform::Enums::Base
      description "The privacy of a sponsorship"

      value "PUBLIC", "Public", value: "public"
      value "PRIVATE", "Private", value: "private"
    end
  end
end
