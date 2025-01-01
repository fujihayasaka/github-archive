# typed: true
# frozen_string_literal: true

require "github/pages/domain_health_checker"

module Pages
  class CertificateErrorComponent < ApplicationComponent
    include PagesHelper

    def initialize(repository:, state:, primary_check: nil, alt_check: nil)
      @repository = repository
      @state = state
      @primary_check = primary_check
      @alt_check = alt_check
    end

    def cname
      @repository.page.cname
    end

    def error_message
      primary_domain_error = @primary_check[:reason] if @primary_check.present?
      alternate_domain_error = @alt_check[:reason] if @alt_check.present?
      alt_domain = get_alt_domain(cname)

      case @state
      when :queued
        {
          scheme:  :warning,
          header:  "#{cname} DNS check is in progress.",
          message: "Please wait for the DNS check to complete."
        }
      when :invalid
        {
          scheme:  :warning,
          header:  "#{cname} is improperly configured",
          message: primary_domain_error
        }
      when :primary_only
        {
          scheme:  :warning,
          header:  "#{alt_domain} is improperly configured",
          message: alternate_domain_error
        }
      when :alternate_only
        {
          scheme:  :danger,
          header:  "#{cname} is improperly configured",
          message: primary_domain_error
        }
      when :both_invalid
        {
          scheme:  :danger,
          header:  "Both #{cname} and its alternate name are improperly configured",
          message: primary_domain_error
        }
      end
    end

  end
end
