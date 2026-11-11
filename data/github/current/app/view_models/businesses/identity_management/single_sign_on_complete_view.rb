# typed: true
# frozen_string_literal: true

module Businesses::IdentityManagement
  class SingleSignOnCompleteView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :business, :sso_error, :fallback_url
  end
end
