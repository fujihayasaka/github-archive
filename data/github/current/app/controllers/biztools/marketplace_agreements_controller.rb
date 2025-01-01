# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceAgreementsController < BiztoolsController

  before_action :marketplace_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :new, :show], optional: true

  def index
    agreements = Marketplace::Agreement.latest.order(id: :desc).paginate(page: current_page, per_page: 20)

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "biztools/marketplace_agreements/agreements", locals: { agreements: agreements }
        else
          render "biztools/marketplace_agreements/index", locals: { agreements: agreements }
        end
      end
    end
  end

  def show
    _, id = Platform::Helpers::NodeIdentification.from_global_id(params[:id])
    agreement = Marketplace::Agreement.find(id)

    respond_to do |format|
      format.html do
        render "biztools/marketplace_agreements/show", locals: {
          version: agreement.version,
          signatory_type: agreement.signatory_type.humanize,
          created_at: agreement.created_at,
          body_html: Platform::Helpers::MarketplaceListingContent.html_for(agreement, :body, { current_user: current_user }),
        }
      end
    end
  end

  def new
    latest_integrator_agreement_version = Marketplace::Agreement.integrator.latest.order(id: :desc).first&.version
    latest_end_user_agreement_version = Marketplace::Agreement.end_user.latest.order(id: :desc).first&.version

    render "biztools/marketplace_agreements/new", locals: {
      latest_integrator_agreement_version: latest_integrator_agreement_version,
      latest_end_user_agreement_version: latest_end_user_agreement_version,
    }
  end

  def create
    inputs = marketplace_agreement_params
    agreement = Marketplace::Agreement.new(
      body: inputs[:body],
      version: inputs[:version],
      signatory_type: inputs[:signatoryType].to_s.downcase.to_sym
    )

    if agreement.save
      redirect_to biztools_marketplace_agreement_path(agreement.global_relay_id)
    else
      errors = agreement.errors.full_messages.join(", ")
      flash[:error] = "Could not create a Marketplace agreement: #{errors}"
      redirect_to biztools_new_marketplace_agreement_path
    end
  end

  private

  def marketplace_agreement_params
    params.require(:marketplace_agreement).permit(:version, :body, :signatoryType)
  end
end
