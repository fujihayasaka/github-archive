# typed: true
# frozen_string_literal: true

module Dependabot
  class PackageEcosystemIconComponent < ApplicationComponent
    include SvgHelper
    include ViewComponent::InlineTemplate

    erb_template <<~'ERB'
      <%= svg("dependabot/#{icon_name}.svg", aria: true, title: icon_name, class: "octicon", width: 16, height: 16) %>
    ERB

    def initialize(package_ecosystem:)
      @package_ecosystem = package_ecosystem
    end

    def icon_name
      Dependabot.serialize_package_ecosystem(package_ecosystem: @package_ecosystem)
    end
  end
end
