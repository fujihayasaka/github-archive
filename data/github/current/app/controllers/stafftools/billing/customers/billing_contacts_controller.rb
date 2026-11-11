# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class BillingContactsController < StafftoolsController
        before_action :dotcom_required
        before_action :stafftools_billing_staff_required!
        before_action :set_customer

        depends_on_clusters ApplicationRecord::Mysql1,
          ApplicationRecord::Billing,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Ballast,
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::Repositories,
          only: [:show]

        sig { void }
        def show
          customer = T.must(@customer)
          billing_contact = customer.billing_contact

          render("stafftools/billing/customers/billing_contacts/show", locals: {
            customer: customer,
            billing_contact: billing_contact,
          })
        end

        private

        sig { void }
        def set_customer
          @customer = T.let(@customer, T.nilable(Customer))
          @customer = Customer.find_by(id: params[:customer_id])
          render_404 unless @customer
        end

        sig { void }
        def stafftools_billing_staff_required!
          render_404 unless current_user&.site_admin?
        end
      end
    end
  end
end
