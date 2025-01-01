# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DsaContentFormatType < Platform::Enums::Base
      description "Represents format type(s) of Digital Services Act (DSA) violating content"
      visibility :internal

      value "TEXT", description: "Content contains text", value: :TEXT
      value "IMAGE", description: "Content contains images", value: :IMAGE
    end
  end
end
