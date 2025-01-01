# typed: strict
# frozen_string_literal: true

module Codespaces
  class PortPrivacySetting

    sig { returns(String) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :display_name

    sig { returns(String) }
    attr_reader :display_description

    sig { params(name: String, display_name: String, display_description: String).void }
    def initialize(name:,
                   display_name:,
                  display_description:)
      @name = name
      @display_name = display_name
      @display_description = display_description
    end
  end
end
