# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class EnterpriseLicensingController < BusinessBaseController
      include ApplicationController::VerifiedFetchDependency
      include BusinessLicenseConsumptionExportHelper

      allow_verified_fetch only: [:create_export, :export]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        ApplicationRecord::Configurations,
        only: [:show]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:show], optional: true

      def show
        respond_to do |format|
          format.html do
            transition = this_business.customer.licensing_model_transitions.last

            render "stafftools/businesses/enterprise_licensing/show", locals: {
              view: Stafftools::Businesses::EnterpriseLicensingView.new(business: this_business),
              transition: transition,
            }
          end

          format.csv do
            send_data Business::LicenseCsvGenerator.new(this_business).generate,
              filename: "#{this_business.slug}-consumed_licenses.csv"
          end
        end
      end

      def update
        this_business.update_license_usage
        BusinessUserAccountsSynchronizeJob.perform_later(business_id: this_business.id)
        flash[:notice] = "Running license usage recalculation in the background. This could take a minute for larger accounts."
        redirect_to stafftools_enterprise_licensing_path(this_business)
      end

      def reconcile_licenses_with_billing_platform # rubocop:todo GitHub/UseRestfulActions
        ::Licensing::ReconcileLicensesWithBillingPlatformJob.perform_later(this_business)
        flash[:notice] = "Running billing platform license reconciliation job in the background. This could take a few minutes for larger accounts."
        redirect_to stafftools_enterprise_licensing_path(this_business)
      end

      def export # rubocop:todo GitHub/UseRestfulActions
        export = this_business.license_consumption_exports.find_by_token!(params[:token])
        render_business_license_consumption_export(export)
      end

      def create_export # rubocop:todo GitHub/UseRestfulActions
        options = {
          actor: current_user,
          format: params[:export_format],
          triggered_via_stafftools: true,
        }

        export = this_business.license_consumption_exports.create(options)
        respond_with_business_license_consumption_export \
          export: export,
          export_url: export_stafftools_enterprise_licensing_url(token: export.token, format: export.format)
      end

      def transition_licensing_model # rubocop:todo GitHub/UseRestfulActions
        transition = ::Licensing::LicensingModelTransition.create!(
          customer: this_business.customer,
          transition_date: params[:transition_date].presence || Date.current,
          licensing_model: licensing_model,
          status: "scheduled",
          actor: current_user,
          reset_ghas_configuration: params[:reset_ghas_configuration] == "1",
          ghas_only: false
        )

        if transition.transition_date == Date.current
          transition.enqueue
          flash[:notice] = "The licensing model for this enterprise will change to #{licensing_model}. This could take a while for larger accounts."
        else
          flash[:notice] = "The licensing model for this enterprise will change to #{licensing_model} on #{transition.date}."
        end

        redirect_to stafftools_enterprise_licensing_path(this_business)
      end

      def cancel_transition # rubocop:todo GitHub/UseRestfulActions
        transition = ::Licensing::LicensingModelTransition.find(params[:transition_id])

        transition.cancel!

        flash[:notice] = "Licensing model transition scheduled for #{transition.date} has been cancelled."

        redirect_to stafftools_enterprise_licensing_path(this_business)
      end

      private

      def licensing_model
        params[:licensing_model]
      end

      def json_request?
        request.format.symbol == :json
      end

      def usage_type
        params[:type]&.downcase&.to_sym
      end
    end
  end
end
