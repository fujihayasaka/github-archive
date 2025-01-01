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
            if FeatureFlag.vexi.enabled?(:update_license_usage_on_licensing_page_load, this_business, default: false)
              # Update the license usage when the page is loaded. This should improve scenarios where the license usage is not up to date
              # due to dotcom's prior run of the job having run before Licensify processed some change event.
              this_business&.update_license_usage
            end

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
        unbundle_ghas = params[:unbundle_ghas] == "1" ? :unbundle_ghas : :bundle_ghas

        transition = T.must(this_business.customer).new_licensing_model_transition(
          licensing_model: licensing_model,
          transition_date: params[:transition_date].presence || Date.current,
          actor: current_user,
          reset_ghas_configuration: params[:reset_ghas_configuration] == "1",
          unbundle_ghas:,
          ghas_only: params[:ghas_only] == "1",
        )

        unless transition.apply_coupon_code(params[:coupon_code])
          if transition.errors[:coupon_code].any?
            flash[:error] = "Coupon could not be applied. Please remove the coupon code to continue with the transition."
            redirect_to stafftools_enterprise_licensing_path(this_business)
            return
          end
        end

        unless transition.save
          flash[:error] = transition.errors.full_messages.join(", ")
          redirect_to stafftools_enterprise_licensing_path(this_business)
          return
        end

        flash_message = if transition.scheduled_for_today?
          transition.enqueue
          "The licensing model for this enterprise will change to #{licensing_model}. This could take a while for larger accounts."
        else
          "The licensing model for this enterprise will change to #{licensing_model} on #{transition.date}."
        end

        if transition.coupon_code?
          flash_message += " Please verify the coupon successfully applies to the business."
        end

        flash[:notice] = flash_message

        redirect_to stafftools_enterprise_licensing_path(this_business)
      end

      def cancel_transition # rubocop:todo GitHub/UseRestfulActions
        transition = this_business.customer.licensing_model_transitions.find(params[:transition_id])

        unless transition.scheduled?
          flash[:alert] = "Unable to cancel this transition."
          redirect_to stafftools_enterprise_licensing_path(this_business) and return
        end

        transition.cancelled!

        flash[:notice] = "Licensing model transition scheduled for #{transition.date} has been cancelled."

        redirect_to stafftools_enterprise_licensing_path(this_business)
      end

      def execute_scheduled_transition # rubocop:todo GitHub/UseRestfulActions
        transition = this_business.customer.licensing_model_transitions.find(params[:transition_id])

        unless transition.scheduled?
          flash[:alert] = "Unable to execute this transition."
          redirect_to stafftools_enterprise_licensing_path(this_business) and return
        end

        transition.update!(transition_date: Date.current, actor: current_user)
        transition.enqueue

        flash[:notice] = "The licensing model for this enterprise will change to #{transition.licensing_model}. This could take a while for larger accounts."

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
