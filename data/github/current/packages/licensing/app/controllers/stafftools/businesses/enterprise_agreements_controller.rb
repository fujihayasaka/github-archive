# typed: true
# frozen_string_literal: true

module Stafftools
  module Businesses
    class EnterpriseAgreementsController < BusinessBaseController
      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Billing,
        ApplicationRecord::Repositories,
        only: [:edit]

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Ballast,
        ApplicationRecord::Repositories,
        ApplicationRecord::Billing,
        only: [:new]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:edit, :new],
        optional: true

      def new
        enterprise_agreement = this_business.enterprise_agreements.new
        render_form(
          enterprise_agreement: enterprise_agreement,
          form_url: stafftools_enterprise_agreements_path(this_business),
          action: :create,
        )
      end

      def edit
        enterprise_agreement = this_business.enterprise_agreements.find(params[:id])
        render_form(
          enterprise_agreement: enterprise_agreement,
          form_url: stafftools_enterprise_agreement_path(this_business, enterprise_agreement),
          action: :update,
        )
      end

      def create
        enterprise_agreement = this_business.enterprise_agreements.new(enterprise_agreement_params)

        if enterprise_agreement.save
          flash[:notice] = "Enterprise agreement updated."
          redirect_to stafftools_enterprise_path(this_business)
        else
          flash[:error] = "Failed to update enterprise agreement. (#{enterprise_agreement.errors.full_messages.to_sentence})"
          render_form(
            enterprise_agreement: enterprise_agreement,
            form_url: stafftools_enterprise_agreements_path(this_business),
            action: :create,
          )
        end
      end

      def update
        enterprise_agreement = this_business.enterprise_agreements.find(params[:id])

        if enterprise_agreement.update(enterprise_agreement_params)
          flash[:notice] = "Enterprise agreement updated."
          redirect_to stafftools_enterprise_path(this_business)
        else
          flash[:error] = "Failed to update enterprise agreement. (#{enterprise_agreement.errors.full_messages.to_sentence})"
          render_form(
            enterprise_agreement: enterprise_agreement,
            form_url: stafftools_enterprise_agreement_path(this_business, enterprise_agreement),
            action: :update,
          )
        end
      end

      def destroy
        enterprise_agreement = this_business.enterprise_agreements.find(params[:id])
        enterprise_agreement.destroy

        redirect_to stafftools_enterprise_path(this_business)
      end

      private

      def render_form(enterprise_agreement:, form_url:, action:)
        render "stafftools/businesses/enterprise_agreements/form", locals: {
          enterprise_agreement: enterprise_agreement,
          form_url: form_url,
          this_business: this_business,
          categories: ::Licensing::EnterpriseAgreement::CATEGORIES,
          statuses: ::Licensing::EnterpriseAgreement::STATUSES,
          action: action,
        }
      end

      def enterprise_agreement_params
        params.require(:enterprise_agreement).permit(
          :agreement_id,
          :category,
          :seats,
          :status,
        )
      end
    end
  end
end
