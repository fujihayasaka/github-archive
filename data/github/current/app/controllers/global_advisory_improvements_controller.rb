# typed: true
# frozen_string_literal: true

require "advisory_db_toolkit"

class GlobalAdvisoryImprovementsController < ApplicationController
  before_action :require_advisory
  before_action :redirect_to_dotcom_if_enterprise
  before_action :login_required
  before_action :redirect_if_spammy_user
  before_action :redirect_if_emu

  javascript_bundle :advisories
  stylesheet_bundle :advisories

  include GitHub::RateLimitedRequest

  rate_limit_requests(
    only: :create,
    max: 10,
    key: :advisories_improvement_rate_limit_key,
    ttl: 1.hour,
    at_limit: :render_advisories_improvement_rate_limit,
  )

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  def new
    override_analytics_location "/advisories/<id>/improve"

    if advisory.vulnerable_version_ranges.size == 0
      advisory.vulnerable_version_ranges.new
    end
    view = create_view_model(
      GlobalAdvisories::ShowView,
      advisory: advisory,
    )
    render "global_advisory_improvements/new", locals: { view: view }
  end

  def create
    form = AdvisoryImprovementForm.new(vulnerability_params, advisory, current_user)

    view = create_view_model(
      GlobalAdvisories::ShowView,
      advisory: form.updated_advisory,
      justification: form.justification,
    )

    if !form.valid?
      flash.now[:error] = "We were not able to process your request because some field values were not properly filled: #{form.updated_advisory.errors.full_messages.join(";").downcase}. Please revisit the form and submit it again with the values corrected."
      render "global_advisory_improvements/new", status: :unprocessable_entity, locals: { view: view }
    elsif !form.changed?
      flash.now[:error] = "We were not able to process your request because it looks like you did not propose any new suggestions to the existing security advisory. Please revisit the form and submit it again with the new proposed changes."
      render "global_advisory_improvements/new", status: :unprocessable_entity, locals: { view: view }
    else
      pull_request_creator = AdvisoryDB::AdvisoryImprovementPullRequestCreator.new(current_user, advisory, form)

      begin
        redirect_to(
          pull_request_path(pull_request_creator.create_or_update_pull_request!),
          notice: "Thank you for submitting an improvement request! Our curators will review your contribution."
        )
      rescue AdvisoryDBToolkit::OSV::Transformers::SchemaV1::UnsupportedOSVEcosystem => error
        Failbot.report(error)
        render "global_advisory_improvements/new", status: :unprocessable_entity, locals: { view: view }
      rescue AdvisoryDBToolkit::OSV::Transformers::SchemaV1::AffectedPackageVersions::RangeOperatorError => error
        flash.now[:error] = "The > operator is not supported. Please correct the Affected Versions to indicate when the vulnerability was introduced."
        render "global_advisory_improvements/new", status: :unprocessable_entity, locals: { view: view }
      rescue AdvisoryDB::AdvisoryImprovementPullRequestCreator::AdvisoriesRepositoryError => error
        Failbot.report(error)
        flash.now[:error] = "We were not able to process your request because our systems are currently experiencing issues. Please try again later."
        render "global_advisory_improvements/new", status: :service_unavailable, locals: { view: view }
      end
    end
  end

  private

  def advisories_improvement_rate_limit_key
    "advisories_improvement_limiter:#{current_user.id}:#{advisory.ghsa_id}"
  end

  def render_advisories_improvement_rate_limit
    GitHub.dogstats.increment("global_advisories.improvment_rate_limited")
  end

  def redirect_to_dotcom_if_enterprise
    if GitHub.single_or_multi_tenant_enterprise?
      redirect_to "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}" + new_global_advisory_improvement_path(advisory.ghsa_id)
    end
  end

  def redirect_if_spammy_user
    if current_user.spammy?
      redirect_to global_advisory_path(advisory.ghsa_id), flash: { error: "You cannot submit an improvement at this time because your account is flagged." }
    end
  end

  def redirect_if_emu
    if current_user.is_enterprise_managed?
      redirect_to global_advisory_path(advisory.ghsa_id), flash: { error: "You cannot contribute to repositories outside of your enterprise #{current_user&.enterprise_managed_business&.name}." }
    end
  end

  memoize def advisory
    Vulnerability.find_by(ghsa_id: params[:id])
  end

  # Advisories are public

  # CAP bypass is fine here as advisories are public.
  def target_for_conditional_access
    if advisory
      advisory.target_for_conditional_access
    else
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  def ip_allowlist_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  # This overrides a setting that was prevent us from routing to the advisories page because
  # it was expecting an SAML SSO target event though we don't need to have one for now
  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end

  def require_advisory
    render_404 unless !advisory&.malware? && advisory&.readable_by?(current_user)
  end

  def vulnerability_params
    params.require(:vulnerability).permit(
      :description,
      :cvss_v3,
      :cvss_v4,
      :justification,
      :severity,
      :source_code_location,
      :summary,
      :vulnerability_references,
      cwes: [],
      vulnerable_version_ranges: [
        :affects,
        :ecosystem,
        :ecosystem_other,
        :fixed_in,
        :requirements,
        :affected_functions,
      ]
    )
  end
end
