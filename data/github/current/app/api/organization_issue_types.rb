# typed: true
# frozen_string_literal: true

class Api::OrganizationIssueTypes < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Scientist
  include FeatureFlagHelper
  include Api::DatabaseResourceUpdateRateLimiting

  get "/organizations/:organization_id/issue-types", operation_id: "orgs/list-issue-types" do
    org = find_org!
    deliver_error!(404) unless org && org.issue_types_enabled?

    control_access :list_org_issue_types,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue_types = org.async_readable_issue_types_matrix(current_user).then do |matrix|
      org.async_issue_types.then do |types|
        types.select { |type| type.readable?(matrix) }
      end
    end.sync

    deliver :type_hash, issue_types
  end

  post "/organizations/:organization_id/issue-types", operation_id: "orgs/create-issue-type" do
    org = find_org!
    deliver_error!(404) unless org && org.issue_types_enabled?

    control_access :write_org_issue_types,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    issue_type = IssueType.new(
      owner: org,
      name: data["name"],
      description: data["description"],
      color: data["color"]&.to_sym,
      enabled: data["is_enabled"]
    )

    unless issue_type.save
      deliver_error!(422, message: "An error occurred while creating the issue type. #{issue_type.errors.full_messages.to_sentence}")
    end

    deliver :type_hash, issue_type
  end

  put "/organizations/:organization_id/issue-types/:issue_type_id", operation_id: "orgs/update-issue-type" do
    org = find_org!
    deliver_error!(404) unless org && org.issue_types_enabled?

    control_access :write_org_issue_types,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue_type = org.issue_types.find_by(id: params[:issue_type_id].to_i)

    deliver_error!(404) unless issue_type

    check_database_resource_update_rate_limit!(resource: issue_type, current_user: current_user)

    data = receive_with_openapi

    updates = {
      name: data["name"],
      description: data["description"],
      enabled: data["is_enabled"],
      color: data["color"]&.to_sym
    }

    issue_type.update(updates)

    unless issue_type.save
      deliver_error!(422, message: "An error occurred while updating the issue type. #{issue_type.errors.full_messages.to_sentence}")
    end

    deliver :type_hash, issue_type
  end

  delete "/organizations/:organization_id/issue-types/:issue_type_id", operation_id: "orgs/delete-issue-type" do
    org = find_org!
    deliver_error!(404) unless org && org.issue_types_enabled?

    control_access :write_org_issue_types,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue_type = org.issue_types.find_by(id: params[:issue_type_id].to_i)

    deliver_error!(404) unless issue_type

    issue_type.destroy

    unless issue_type.destroyed?
      deliver_error!(422, message: "An error occurred while deleting the issue type. #{issue_type.errors.full_messages.to_sentence}")
    end

    deliver_empty status: 204
  end
end
