# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SupportLinkType < Platform::Enums::Base
      description "The possible support link types."
      required_capabilities [:mobile_only_schema_mask]

      value "EMAIL", "A email support link", value: "email"
      value "URL", "A url support link", value: "url"
    end
  end
end
