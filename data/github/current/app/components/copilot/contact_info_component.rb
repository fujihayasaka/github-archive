# typed: true
# frozen_string_literal: true

module Copilot
  class ContactInfoComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    include ReactHelper
    include TradeControlsHelper

    def initialize(user:, form:, show_contact_info: false)
      @user = user
      @f = form
      @show_contact_info = show_contact_info
    end

    private

    attr_reader :user, :f

    def render?
      @show_contact_info
    end

    def account_type
      if user.organization?
        "Organization"
      elsif user.business?
        "Enterprise"
      else
        "Personal"
      end
    end

    def primary_email
      user.primary_email_address.email
    end
  end
end
