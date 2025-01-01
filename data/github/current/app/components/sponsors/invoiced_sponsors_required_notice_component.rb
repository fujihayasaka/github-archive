# typed: strict
# frozen_string_literal: true

module Sponsors
  class InvoicedSponsorsRequiredNoticeComponent < ApplicationComponent
    extend T::Sig

    sig { params(sponsor_login: String, system_arguments: T.untyped).void }
    def initialize(sponsor_login:, **system_arguments)
      @sponsor_login = sponsor_login
      @system_arguments = system_arguments
      @system_arguments[:test_selector] ||= "invoiced-sponsors-required-notice"
    end

    private

    sig { returns(String) }
    attr_reader :sponsor_login
  end
end
