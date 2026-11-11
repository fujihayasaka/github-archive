# typed: true
# frozen_string_literal: true

module Orgs::IdentityManagement
  class SingleSignOnCompleteView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :organization, :saml_error, :fallback_url
  end
end
