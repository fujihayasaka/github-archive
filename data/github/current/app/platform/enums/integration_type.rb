# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IntegrationType < Platform::Enums::Base
      description "Indicates which kind of integration"
      visibility :internal

      value "GITHUB_APP", "GitHub Apps", value: "github_app"
      value "OAUTH", "OAuth Application", value: "oauth"
      value "NONE", "OAuth Application", value: "none"
    end
  end
end
