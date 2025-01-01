# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class EnterpriseLicensingController < BusinessBaseController
      include ApplicationController::VerifiedFetchDependency

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
        ApplicationRecord::Notify,
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

      def transition_licensing_model # rubocop:todo GitHub/UseRestfulActions
        transition = T.must(this_business.customer).new_licensing_model_transition(
          licensing_model: licensing_model,
          transition_date: params[:transition_date].presence || Date.current,
          actor: current_user,
          reset_ghas_configuration: params[:reset_ghas_configuration] == "1",
          unbundle_ghas: params[:unbundle_ghas] == "1",
          ghas_only: params[:ghas_only] == "1",
        )

        apply_coupon_code = params[:coupon_code].present? && licensing_model == "volume"
        transition.coupon_code = params[:coupon_code] if apply_coupon_code
        transition.save!

        flash_message = ""
        if transition.transition_date == Date.current
          transition.enqueue
          flash_message = "The licensing model for this enterprise will change to #{licensing_model}. This could take a while for larger accounts."
        else
          flash_message = "The licensing model for this enterprise will change to #{licensing_model} on #{transition.date}."
        end

        if apply_coupon_code
          flash_message += " Please verify the coupon successfully applies to the business."
        end

        flash[:notice] = flash_message

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
