# typed: true
# frozen_string_literal: true

class Orgs::SecurityAndAnalysis::CodeScanning::ModelPackSettingsController < Orgs::Controller

  def self.react_bundle_name
    "code-scanning-organization-model-pack-settings"
  end

  before_action :login_required
  before_action :manage_security_products_permission_required

  track_availability_slo "ui-request"
  track_latency_slo "p50-ui-request", 500
  track_latency_slo "p99-ui-request", 2000

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    only: [:edit]

  def edit
    form_url = settings_org_code_scanning_update_model_packs_path
    form_method = :put
    existing_model_packs = CodeScanningOrgConfigurations.
      where(organization_id: current_organization.id).pluck(:codeql_packs).first || ""

    add_csrf_token(form_url, form_method)

    render_react_app(
      payload: {
        orgSecurityAnalysisUrl: settings_org_security_analysis_path,
        formUrl: form_url,
        formMethod: form_method,
        existingModelPacks: existing_model_packs,
        defaultSetupUrl: DocsUrlConfig.url_for("code-scanning/configuring-default-setup-for-code-scanning"),
        aboutCodeqlPacksUrl: DocsUrlConfig.url_for("code-scanning/extending-codeql-coverage-with-codeql-model-packs-in-default-setup", ghec: true),
        codeqlPackPublishUrl: DocsUrlConfig.url_for("codeql-cli/running-codeql-pack-publish"),
      },
      page_data: {
        selected_link: :security_analysis,
        title: "Code Scanning model packs"
      },
      layout: "organization_settings",
      disable_ssr: true,
    )
  end

  def update
    new_model_packs = params[:code_scanning_org_level_model_packs]
    # We rely on client side validation to check the syntax of the packs field,
    # so we only perform a simple validation here (that size < 10k).
    # If people call the endpoint without the client side validation, we
    # allow them to save bogus data in the DB.
    # CodeQL is expected to just warn about this data when running.
    if valid_model_packs?(new_model_packs)
      CodeScanningOrgConfigurations.upsert({ organization_id: current_organization.id, codeql_packs: new_model_packs })
      flash[:notice] = "CodeQL model packs updated."
    end

    redirect_to settings_org_security_analysis_path
  end

  private

  # valid_model_packs? returns true if the packs are valid and can be stored in the DB.
  # Note that this doesnt imply that they follow the correct syntax, just that they
  # are not too large for the DB.
  def valid_model_packs?(new_model_packs)
    return false if new_model_packs.nil?
    return false if new_model_packs.length > 10000

    true
  end

end
