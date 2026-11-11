# typed: true
# frozen_string_literal: true

class Businesses::People::ExternalIdentitiesController < Businesses::BusinessController
  before_action :write_enterprise_sso_required
  before_action :dotcom_required
  before_action :person_required
  before_action :sso_enabled_required
  before_action :business_not_downgraded_to_free_plan_required

  def destroy
    ExternalIdentity.unlink(
      provider: this_business.external_provider,
      user: person,
      instrumentation_payload: {
        actor: current_user,
        user: person,
      },
    )

    flash[:notice] = "External identity for #{person} successfully revoked."
    redirect_to enterprise_person_sso_enterprise_path(this_business, person)
  end
end
