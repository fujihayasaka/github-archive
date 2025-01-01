# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::AgreementsController < StafftoolsController
  extend T::Sig

  AGREEMENTS_PER_PAGE = 30
  SIGNATURES_PER_PAGE = 10
  SIGNATURE_SORT_PARAM = :signatures_sort_by

  before_action :sponsors_required
  before_action :require_agreement, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:index, :show, :new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new], optional: true

  sig { void }
  def new
    agreement = SponsorsAgreement.new(kind: :invoiced_sponsor)
    render "stafftools/sponsors/agreements/new", locals: { agreement: agreement }
  end

  sig { void }
  def create
    agreement = SponsorsAgreement.new(agreement_params)
    if agreement.save
      flash[:notice] = "Agreement successfully created."
      redirect_to stafftools_sponsors_agreement_path(agreement)
    else
      flash[:error] = "Couldn't create agreement: #{agreement.errors.full_messages.to_sentence}"
      render "stafftools/sponsors/agreements/new", locals: { agreement: agreement }
    end
  end

  sig { void }
  def index
    # Relations are loaded in Stafftools::Sponsors::AgreementsListComponent, to avoid n+1 queries
    agreements = SponsorsAgreement.order(kind: :desc).newest_first
      .paginate(page: current_page, per_page: AGREEMENTS_PER_PAGE)

    respond_to do |format|
      format.html do
        if request.xhr? || pjax?
          render Stafftools::Sponsors::AgreementsListComponent.new(agreements: agreements), layout: false
        else
          render "stafftools/sponsors/agreements/index", locals: { agreements: agreements }
        end
      end
    end
  end

  sig { returns(T.untyped) }
  def show
    respond_to do |format|
      format.html do
        if request.xhr? || pjax?
          render Stafftools::Sponsors::Invoiced::SignatureListComponent.new(
            signatures: signatures,
            agreement: agreement,
          ), layout: false
        else
          render "stafftools/sponsors/agreements/show", locals: {
            agreement: agreement,
            signatures: signatures,
            signature_order: signature_order,
          }
        end
      end
    end
  end

  private

  sig { returns(SponsorsAgreement) }
  def agreement
    SponsorsAgreement.find(params[:id])
  end

  sig { returns(ActionController::Parameters) }
  def agreement_params
    params.require(:sponsors_agreement).permit(:kind, :body, :version, :organization_login, :organization_id)
  end

  sig { void }
  def require_agreement
    render_404 unless agreement.present?
  end

  sig { returns(T.any(WillPaginate::Collection, ActiveRecord::Relation)) }
  memoize def signatures
    return SponsorsInvoicedAgreementSignature.none unless agreement.invoiced_sponsor_kind?

    signatures = agreement.invoiced_signatures.order(signature_order.ordering_arguments)
    signatures.paginate(page: current_page, per_page: SIGNATURES_PER_PAGE)
  end

  sig { returns(SponsorsAgreement::Signatures::SortOption) }
  memoize def signature_order
    SponsorsAgreement::Signatures::SortOption.try_deserialize(
      params[SIGNATURE_SORT_PARAM]
    ) || SponsorsAgreement::Signatures::SortOption::RecentlySigned
  end
end
