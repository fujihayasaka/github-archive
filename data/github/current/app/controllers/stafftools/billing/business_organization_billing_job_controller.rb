# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class BusinessOrganizationBillingJobController < StafftoolsController
      include ApplicationController::VerifiedFetchDependency

      before_action :dotcom_required

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Ballast,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Repositories,
        ApplicationRecord::Configurations,
        only: [:index]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index],
        optional: true

      allow_verified_fetch only: [:index, :perform]

      sig { returns(String) }
      def self.react_bundle_name
        "billing-app"
      end

      sig { void }
      def index
        failed_business_transitions = ::Organization.failed_billing_transition
        orgs = failed_business_transitions.map do |failed_business_transition|
          org_as_json(org: failed_business_transition)
        end
        render_react_app(
          payload: {
            orgs: orgs,
          },
          title: "Business Organization Billing Job",
          layout: "layouts/stafftools/react_stafftools",
        )
      end

      sig { void }
      def perform # rubocop:todo GitHub/UseRestfulActions
        org = ::Organization.find(params[:id])

        begin
          BusinessOrganizationBillingJob.perform_now(T.must(org.business), org)
        rescue Exception => e
          return render(json: { error: "#{e.class}: #{e.exception}" }, status: 500)
        end

        render_react_app(payload: {})
      end

      private

      sig { params(org: ::Organization).returns(T.nilable(Hash)) }
      def org_as_json(org:)
        return nil if org.nil?
        {
          id: org.id,
          login: org.login,
          business: {
            slug: T.must(org.business).slug
          }
        }
      end
    end
  end
end
