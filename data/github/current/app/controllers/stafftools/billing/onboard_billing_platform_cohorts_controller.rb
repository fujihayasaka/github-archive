# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class OnboardBillingPlatformCohortsController < StafftoolsController
      CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
        "Stafftools::Billing::OnboardBillingPlatformCohortsController#create",
      ]

      depends_on_clusters(
        ApplicationRecord::Ballast,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        only: [:index, :create, :show],
      )

      sig { void }
      def index
        cohorts = ::Billing::BillingPlatformOnboardingCohort.all
        render "stafftools/billing/onboard_billing_platform_cohorts/index", locals: { cohorts: cohorts }
      end

      sig { void }
      def create
        ::Billing::OnboardCohortMembersToBillingPlatformJob.perform_later(
          cohort_name: params[:cohort_name],
        )

        flash[:notice] = "Cohort \"#{params[:cohort_name]}\" onboarding has been enqueued. Members of this cohort will be onboarded to billing platform shortly."
        redirect_to stafftools_billing_onboard_billing_platform_cohorts_path
      end

      sig { void }
      def show
        customers = ::Billing::BillingPlatformOnboardingCohort
          .customers(cohort_name: params[:id])
          .paginate(page: params[:page], per_page: 25)

        render("stafftools/billing/onboard_billing_platform_cohorts/show", locals: {
          customers: customers,
          cohort_name: params[:id]
        })
      end
    end
  end
end
