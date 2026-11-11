# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::ContentExclusion < Api::App
  include FeatureFlagHelper
  include ReceiveSchemaWithOpenApi

  SMALL_PAYLOAD_LIMIT = 100.kilobytes

  get "/organizations/:organization_id/copilot/content_exclusion", operation_id: "copilot/copilot-content-exclusion-for-organization" do
    org = find_org!

    ensure_endpoint_enabled!(org)

    control_access :standard_authorization,
      resource: org,
      permission: :read_org_copilot_content_exclusion,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless content_exclusion_available?(org)

    receive_with_openapi
    content_exclusion_config = Copilot::ContentExclusionConfiguration.for_organization(org).first
    return deliver_raw({}) if content_exclusion_config&.document.blank?

    json = GitHub.dogstats.distribution_time("copilot.api.copilot_content_exclusion.get_org.yaml_deserialize") do
      YAML.safe_load(T.must(content_exclusion_config).document)
    end
    deliver_raw(json)
  end

  put "/organizations/:organization_id/copilot/content_exclusion", operation_id: "copilot/set-copilot-content-exclusion-for-organization", read_from_replicas: true do
    org = find_org!

    ensure_endpoint_enabled!(org)

    control_access :standard_authorization,
      resource: org,
      permission: :write_org_copilot_content_exclusion,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless content_exclusion_available?(org)
    ensure_payload_size!

    data = receive_with_openapi

    content_exclusion_config = Copilot::ContentExclusionConfiguration.for_organization(org).first
    new_paths = if data.blank?
      ""
    else
      GitHub.dogstats.distribution_time("copilot.api.copilot_content_exclusion.put_org.serialize_yaml") do
        data.to_yaml
      end
    end

    if content_exclusion_config.present?
      GitHub.logger.info("Updating ContentExclusionConfiguration via API", "gh.org.id" => org.id, "gh.copilot_ignore_config.id" => content_exclusion_config.id)
      content_exclusion_config.assign_attributes(document: new_paths, updated_by: current_user)
    else
      GitHub.logger.info("Creating ContentExclusionConfiguration via API", "gh.org.id" => org.id)
      content_exclusion_config = Copilot::ContentExclusionConfiguration.new(
        resource: org,
        resource_type: "Organization",
        updated_by: current_user,
        document: new_paths
      )
    end

    unless content_exclusion_config.valid?
      deliver_error!(422, message: "Invalid request.", errors: content_exclusion_config.errors.full_messages)
    end

    with_write(clusters: [ApplicationRecord::Copilot]) do
      content_exclusion_config.save!
    end

    deliver_raw({ message: Copilot::COPILOT_CONTENT_EXCLUSION_SUCCESS_MESSAGE }, status: 200)
  end

  get "/enterprises/:enterprise_id/copilot/content_exclusion", operation_id: "copilot/copilot-content-exclusion-for-enterprise" do
    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless content_exclusion_available?(enterprise)

    receive_with_openapi
    content_exclusion_config = Copilot::ContentExclusionConfiguration.for_business(enterprise).first
    return deliver_raw({}) if content_exclusion_config&.document.blank?

    json = GitHub.dogstats.distribution_time("copilot.api.copilot_content_exclusion.get_ent.deserialize_yaml") do
      YAML.safe_load(T.must(content_exclusion_config).document)
    end
    deliver_raw(json)
  end

  put "/enterprises/:enterprise_id/copilot/content_exclusion", operation_id: "copilot/set-copilot-content-exclusion-for-enterprise", read_from_replicas: true do
    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_ai_controls,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_INSUFFICIENT_PERMISSIONS_MESSAGE

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless content_exclusion_available?(enterprise)
    ensure_payload_size!

    data = receive_with_openapi

    content_exclusion_config = Copilot::ContentExclusionConfiguration.for_business(enterprise).first
    new_paths = if data.blank?
      ""
    else
      GitHub.dogstats.distribution_time("copilot.api.copilot_content_exclusion.put_ent.serialize_yaml") do
        data.to_yaml
      end
    end

    if content_exclusion_config.present?
      GitHub.logger.info("Updating ContentExclusionConfiguration via API", "gh.business.id" => enterprise.id, "gh.copilot_ignore_config.id" => content_exclusion_config.id)
      content_exclusion_config.assign_attributes(document: new_paths, updated_by: current_user)
    else
      GitHub.logger.info("Creating ContentExclusionConfiguration via API", "gh.business.id" => enterprise.id)
      content_exclusion_config = Copilot::ContentExclusionConfiguration.new(
        resource: enterprise,
        resource_type: "Business",
        updated_by: current_user,
        document: new_paths
      )
    end

    unless content_exclusion_config.valid?
      deliver_error!(422, message: "Invalid request.", errors: content_exclusion_config.errors.full_messages)
    end

    with_write(clusters: [ApplicationRecord::Copilot]) do
      content_exclusion_config.save!
    end

    deliver_raw({ message: Copilot::COPILOT_CONTENT_EXCLUSION_SUCCESS_MESSAGE }, status: 200)
  end

  def ensure_endpoint_enabled!(actor)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless actor.feature_flag_enabled?(:copilot_content_exclusion_api, default: false)
  end

  def content_exclusion_available?(entity)
    if entity.is_a?(::Organization)
      copilot_org = Copilot::Organization.new(entity)
      # is_available? method already checks if Copilot is enabled for the organization
      ::Copilot::ContentExclusion.is_available?(entity) && (copilot_org.copilot_billable? || copilot_org.on_free_trial?)
    elsif entity.is_a?(::Business)
      Copilot::Business.new(entity).copilot_enabled? && !entity.downgraded_to_free_plan? && !entity.trial? && ::Copilot::ContentExclusion.is_available?(entity)
    else
      false
    end
  end

  def ensure_payload_size!
    max_chars = max_payload_size
    deliver_error!(413, message: "Invalid request. Document is too long (maximum is #{max_chars} characters)") if request.content_length.to_i > max_chars
  end

  def max_payload_size
    # We typically accept ~1MB per document. If this is abused, this flag will reduce it to 100KB, which should still be sufficient for most use cases while mitigating abuse.
    return SMALL_PAYLOAD_LIMIT if FeatureFlag.vexi.enabled?(:copilot_content_exclusions_api_decrease_payload_limit, default: false)

    Copilot::ContentExclusionConfiguration::DOC_CHAR_LIMIT
  end
end
