# typed: true
# frozen_string_literal: true

module SecurityCenter
  class CreateCampaignDialogComponent < ApplicationComponent
    attr_reader :show_button

    def initialize(org:, show_button:)
      @org = org
      @show_button = show_button
    end

    def code_scanning_path(template: nil)
      security_center_alerts_code_scanning_path(org: @org, template:)
    end
  end
end
