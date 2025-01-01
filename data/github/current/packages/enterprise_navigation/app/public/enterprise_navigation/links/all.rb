# typed: strict
# frozen_string_literal: true

module EnterpriseNavigation
  module Links
    module All
      extend T::Helpers

      include EnterpriseNavigation::Links::People
      include EnterpriseNavigation::Links::Policies
      include EnterpriseNavigation::Links::IdentityProvider
      include EnterpriseNavigation::Links::CodeSecurity
      include EnterpriseNavigation::Links::BillingAndLicensing
      include EnterpriseNavigation::Links::Settings
      include EnterpriseNavigation::Links::Compliance
      include EnterpriseNavigation::Links::Insights
      include EnterpriseNavigation::Links::Organizations
    end
  end
end
