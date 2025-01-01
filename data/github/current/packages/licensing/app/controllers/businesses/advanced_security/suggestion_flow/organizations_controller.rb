# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::SuggestionFlow::OrganizationsController < Businesses::AdvancedSecurity::SuggestionFlow::BaseController
  sig { void }
  def show
    render :show
  end

  sig { void }
  def update
    selected_orgs = selected_orgs(params[:selected_org_ids])
    Billing::Kv.store.set(selected_orgs_key, selected_orgs.map(&:id).join(","))
    head :ok
  end

  private

  sig { params(ids: T::Array[Integer]).returns(T::Array[Organization]) }
  def selected_orgs(ids)
    this_business.organizations.where(id: ids).order(:id).limit(1000).to_a
  end
end
