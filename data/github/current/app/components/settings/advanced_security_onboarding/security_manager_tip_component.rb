# typed: strict
# frozen_string_literal: true

module Settings
  module AdvancedSecurityOnboarding
    class SecurityManagerTipComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests

      HELP_URL = T.let("#{GitHub.help_url}/enterprise-cloud@latest/organizations/organizing-members-into-teams/creating-a-team", String)
    end
  end
end
