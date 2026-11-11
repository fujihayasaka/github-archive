# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::EducationConfigurationController < Stafftools::Businesses::BusinessBaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:edit, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    render "stafftools/businesses/education_configuration/show", locals: {
      business: this_business
    }
  end

  def edit
    render "stafftools/businesses/education_configuration/edit", locals: {
      business: this_business
    }, layout: false
  end

  def update
    response = ::Billing::Education::BundleProvisioner.perform!(
      business: this_business,
      education_bundle: params[:education_bundle],
      actor: current_user
    )

    if response.success?
      flash[:notice] = "#{this_business} has been updated to the #{params[:education_bundle]} Bundle."
    else
      flash[:error] = response.error_message
    end

    redirect_to stafftools_enterprise_billing_education_configuration_path(this_business)
  end
end
