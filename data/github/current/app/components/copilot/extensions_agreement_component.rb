# typed: strict
# frozen_string_literal: true

module Copilot
  class ExtensionsAgreementComponent < ApplicationComponent

    sig { returns(Integration) }
    attr_reader :integration

    delegate :owner, to: :integration

    sig { params(integration: Integration).void }
    def initialize(integration)
      @integration = T.let(integration, Integration)
    end

    sig { returns(String) }
    def avatar_href
      return enterprise_path(owner.slug) if owner.is_a?(::Business)

      user_path(owner.display_login)
    end
  end
end
