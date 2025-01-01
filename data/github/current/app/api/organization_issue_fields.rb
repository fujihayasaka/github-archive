# typed: true
# frozen_string_literal: true

class Api::OrganizationIssueFields < Api::App
  include ReceiveSchemaWithOpenApi
  include Api::Issues::EnsureIssuesEnabled
  include Scientist
  include FeatureFlagHelper

  post "/organizations/:organization_id/issue-fields", operation_id: "orgs/create-issue-field", read_from_replicas: true do
    org = find_org!

    control_access :write_org_issue_fields,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless IssueFieldsFeature.enabled?(org, actor: current_user)

    data = receive_with_openapi

    field_attributes = Issues::IssueFieldNewAttributes.new(
         name: data["name"],
         data_type: data["data_type"].to_s,
         description: data["description"]
       )

    result = with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      if data["data_type"] == "single_select"
        options = data["options"]
        if options.nil? || options.empty?
          deliver_error!(422, message: "Options are required for single select fields.")
        end
        single_select_options = options&.map do |option|
          Issues::IssueFieldOptionNewAttributes.new(
            name: option["name"],
            color: option["color"],
            description: option["description"],
            priority: option["priority"]
          )
        end
        Issues.domain.issue_fields.create_single_select_field(
          org: org,
          name: field_attributes.name,
          description: field_attributes.description,
          options: single_select_options,
          actor: current_user
        )
      else
        Issues.domain.issue_fields.create_field(
                   org: org,
                   name: field_attributes.name,
                   data_type: field_attributes.data_type,
                   actor: current_user,
                   description: field_attributes.description
                 )
      end
    end

    issue_field = case result
    when GH::Result::Ok
      result.value
    when GH::Result::Error::Validation
      message = result.model.errors.full_messages.join(", ")
      deliver_error!(422, message: message)
    when GH::Result::Error
      deliver_error!(503, message: "Encountered an error while creating the issue field: #{result.message}")
    end

    deliver :field_hash, issue_field
  end

  patch "/organizations/:organization_id/issue-fields/:issue_field_id", operation_id: "orgs/update-issue-field", read_from_replicas: true do
    org = find_org!

    control_access :write_org_issue_fields,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless IssueFieldsFeature.enabled?(org, actor: current_user)

    issue_field = Issues.domain.issue_fields.issue_field_for_org(params[:issue_field_id].to_i, org)
    deliver_error!(404) unless issue_field

    data = receive_with_openapi

    update_attrs = {}
    update_attrs[:name] = data["name"] if data.key?("name")
    update_attrs[:description] = data["description"] if data.key?("description")

    result = with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      # we keep existing values for fields that were not provided
      field_attributes_params = {}
      field_attributes_params[:priority] = issue_field.priority
      field_attributes_params[:name] = update_attrs.key?(:name) ? update_attrs[:name] : issue_field.name
      field_attributes_params[:description] = update_attrs.key?(:description) ? update_attrs[:description] : issue_field.description
      field_attributes = Issues::IssueFieldUpdateAttributes.new(**field_attributes_params)

      if issue_field.data_type.to_s == "single_select" && data["options"]
        # to pacify TS
        unless issue_field.is_a?(Issues::IIssueFieldSingleSelect)
          deliver_error!(422, message: "Issue field is not a single select field")
        end

        options = data["options"]
        if options.empty?
          deliver_error!(422, message: "Options cannot be empty for single select fields.")
        end
        single_select_options = options.map do |option|
          Issues::IssueFieldOptionUpdateAttributes.new(
            option_id: option["id"] || 0,
            name: option["name"],
            color: option["color"],
            description: option["description"],
            priority: option["priority"]
          )
        end

        Issues.domain.issue_fields.update_single_select_field(
          issue_field: issue_field,
          field_attributes: field_attributes,
          all_options: single_select_options,
          org: org
        )
      else
        Issues.domain.issue_fields.update_field(
          issue_field: issue_field,
          field_attributes: field_attributes,
          org: org
        )
      end
    end

    updated_issue_field = case result
    when GH::Result::Ok
      result.value
    when GH::Result::Error::Validation
      message = result.model.errors.full_messages.join(", ")
      deliver_error!(422, message: message)
    when GH::Result::Error
      deliver_error!(503, message: "Encountered an error while updating the issue field: #{result.message}")
    end

    deliver :field_hash, updated_issue_field
  end

  delete "/organizations/:organization_id/issue-fields/:issue_field_id", operation_id: "orgs/delete-issue-field", read_from_replicas: true do
    org = find_org!

    control_access :write_org_issue_fields,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless IssueFieldsFeature.enabled?(org, actor: current_user)

    result = with_write(clusters: [ApplicationRecord::IssuesPullRequests]) do
      Issues.domain.issue_fields.delete_field_by_id(params[:issue_field_id].to_i, org)
    end

    case result
    when GH::Result::Ok
      deliver_empty status: 204
    when GH::Result::Error::NotFound
      deliver_error!(404, message: "Issue field not found")
    when GH::Result::Error::Validation
      message = result.model.errors.full_messages.join(", ")
      deliver_error!(422, message: message)
    when GH::Result::Error
      deliver_error!(503, message: "Encountered an error while deleting the issue field: #{result.message}")
    end
  end

  get "/organizations/:organization_id/issue-fields", operation_id: "orgs/list-issue-fields", read_from_replicas: true do
    org = find_org!

    control_access :list_org_issue_fields,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error!(404) unless IssueFieldsFeature.enabled?(org, actor: current_user)

    begin
      issue_fields = Issues.domain.issue_fields.by_organization(org, :created_at)
      deliver :field_hash, issue_fields
    rescue ActiveRecord::ActiveRecordError => e
      deliver_error!(500, message: "Error retrieving issue fields: #{e.message}")
    end
  end
end
