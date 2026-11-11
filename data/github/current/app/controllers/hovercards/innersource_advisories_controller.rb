# typed: strict
# frozen_string_literal: true

class Hovercards::InnersourceAdvisoriesController < ApplicationController
  before_action :login_required
  before_action :require_xhr
  before_action :require_advisory

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:show]

  sig { void }
  def show
    view = create_view_model(GlobalAdvisories::ShowView, advisory: advisory)
    render "hovercards/advisories/show", layout: false, locals: { view: view }
  end

  private

  sig { returns(T.nilable(Vulnerability)) }
  memoize def advisory
    return nil unless current_user

    ghsa_id = AdvisoryDB.canonical_case_for_ghsa_id(params[:id])
    Vulnerability.visible_to(current_user.business_ids, current_user.organization_ids)
      .find_by(ghsa_id: ghsa_id)
  end

  sig { void }
  def require_advisory
    render_404 unless advisory&.readable_by?(current_user) && innersource_authorized?(advisory)
  end

  sig { params(vuln: T.nilable(Vulnerability)).returns(T::Boolean) }
  def innersource_authorized?(vuln)
    return false unless vuln

    owner = vuln.owner
    case owner
    when Business
      AdvisoryDB::Innersource.business_authorized?(business: owner)
    when Organization
      AdvisoryDB::Innersource.org_authorized?(org: owner)
    else
      false
    end
  end

  # CAP enforcement: the advisory's owning business or org is the resource/target.
  sig { returns(T.nilable(T.any(Business, Organization, Symbol))) }
  def resource_for_conditional_access
    adv = advisory
    return :no_resource_for_conditional_access unless adv # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    adv.owner
  end

  sig { returns(T.nilable(T.any(Business, Organization, Symbol))) }
  def target_for_conditional_access
    resource_for_conditional_access
  end
end
