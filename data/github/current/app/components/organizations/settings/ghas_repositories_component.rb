# typed: true
# frozen_string_literal: true

class Organizations::Settings::GhasRepositoriesComponent < ApplicationComponent

  include SecurityAnalysisSettingsHelper

  def initialize(organization:, page_param: 1)
    @organization = organization
    @page_param = page_param.to_i
    if @page_param <= 0
      @page_param = 1
    end

    # Note that @organization.advanced_security_license returns the
    # license for the relevant billable entity (org or business), not
    # necessarily for the org on which it's called.
    @advanced_security_license = @organization.advanced_security_license
  end

  def render?
    @organization.advanced_security_purchased?
  end
end
