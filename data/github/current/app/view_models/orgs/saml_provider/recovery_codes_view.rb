# typed: true
# frozen_string_literal: true

module Orgs
  module SamlProvider
    class RecoveryCodesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :organization, :saml_provider

      delegate :formatted_recovery_codes, to: :saml_provider, allow_nil: true
    end
  end
end
