# typed: true
# frozen_string_literal: true

class Api::OrganizationIssueTypes < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Scientist
  include FeatureFlagHelper

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

    if (feature_enabled_globally_or_for_user?(feature_name: :issue_types_prevent_private_type_creation) || GitHub.enterprise?) && data.key?("is_private")
      deliver_error!(400, message: "Argument 'is_private' is no longer supported.")
    end

    issue_type = IssueType.new(
      owner: org,
      name: data["name"],
      description: data["description"],
      color: data["color"]&.to_sym,
      private: data["is_private"] || false,
      enabled: data["is_enabled"]
    )

    unless issue_type.save
      deliver_error!(422, message: "An error occurred while creating the issue type. #{issue_type.errors.full_messages.to_sentence}")
    end

    deliver :type_hash, issue_type
  end

  put "/organizations/:organization_id/issue-types/:issue_type_id", operation_id: "orgs/update-issue-type" do
    unless feature_enabled_globally_or_for_user?(feature_name: :issue_types_rest_api_update)
      deliver_error!(404)
    end

    org = find_org!
    deliver_error!(404) unless org && org.issue_types_enabled?

    control_access :write_org_issue_types,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    issue_type = org.issue_types.find_by(id: params[:issue_type_id].to_i)

    deliver_error!(404) unless issue_type

    data = receive_with_openapi

    if (feature_enabled_globally_or_for_user?(feature_name: :issue_types_prevent_private_type_creation) || GitHub.enterprise?) && data["is_private"]
      deliver_error!(400, message: "Provided value 'true' for 'is_private' is invalid. Private issue types can no longer be created.")
    end

    updates = {
      name: data["name"],
      description: data["description"],
      private: data["is_private"] || false,
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
