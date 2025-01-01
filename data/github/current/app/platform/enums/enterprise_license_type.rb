# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseLicenseType < Platform::Enums::Base
      description "Enterprise license types"
      visibility :internal

      value "ENTERPRISE", "Enterprise", value: "enterprise"
      value "VSS_BUNDLE", "Visual Studio subscription", value: "vss_bundle"
    end
  end
end
