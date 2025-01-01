# typed: strict
# frozen_string_literal: true

class Api::OrganizationCustomPropertiesValues < Api::App
  include CustomProperties::Errors
  include ReceiveSchemaWithOpenApi
  include Repos::ListHelper

  # List all custom property values for all repos in an organization
  get "/organizations/:organization_id/properties/values", operation_id: "orgs/list-custom-properties-values-for-repos" do
    org = find_org!

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_reader_permissions(org)

    repo_query_result = search_org_repos(
      org,
      current_user,
      params[:repository_query],
      pagination[:page],
      per_page: pagination[:per_page],
      cap_filter:,
    )

    property_values_by_repo = CustomProperties::Public.repo_properties(repo_query_result[:repos], :effective)

    data = repo_query_result[:repos].map do |repo|
      {
        repository: repo,
        property_values: property_values_by_repo[repo]
      }
    end

    # The deliver method will automatically set the pagination headers
    # but it needs to know the collection_size. It can infer it if the object passed to deliver
    # is an active record relation or a hash, but in this case it's an array of hashes so we
    # must manually set the collection size.
    paginator.collection_size = repo_query_result[:total]
    deliver :repo_property_effective_values_hash, data
  rescue Search::Query::MaxOffsetError => error
    deliver_error! 422, message: error.message
  end

  # Update provided custom property values for specified repos in an organization
  patch "/organizations/:organization_id/properties/values", operation_id: "orgs/create-or-update-custom-properties-values-for-repos" do
    org = find_org!
    values_manager = ::CustomProperties::Public.values_manager(CustomProperties::Public.definitions_manager(org))

    control_access :edit_org_custom_properties_values,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    track_edit_permissions(org)

    data = receive_with_openapi

    data_properties = data["properties"]
    property_names = data_properties.map { |property| property["property_name"] }

    duplicate_properties = property_names.tally.select { |_prop, count| count > 1 }.keys
    deliver_error! 422, message: "Updated properties must be unique, found duplicates: #{duplicate_properties.join(', ')}" if duplicate_properties.any?

    names = Array(data["repository_names"])
    repos = org.repositories.active.where(name: names).to_a

    missing_names = names - repos.map(&:name)
    deliver_error! 422, message: "Repository name not found: #{missing_names.join(', ')}" if missing_names.any?

    properties = data_properties.to_h { |property| [property["property_name"], property["value"]] }

    begin
      values_manager.set_properties_for(repos, properties, actor: current_actor)
      deliver_empty status: 204
    rescue PropertyValidationError, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end

  sig { params(org: Organization).void }
  def track_reader_permissions(org)
    return unless GitHub.flipper[:track_org_custom_properties_perms].enabled?

    access_through_org_custom_properties_reader = if current_user.can_have_granular_permissions?
      org.resources.organization_custom_properties.readable_by?(current_user)
    else
      org.member?(current_user)
    end

    access_through_member_reader = org.resources.members.readable_by?(current_user)

    tag_value = if access_through_org_custom_properties_reader && access_through_member_reader
      "both"
    elsif access_through_org_custom_properties_reader
      "org_props_reader"
    else
      "member_reader"
    end

    GitHub.dogstats.increment("repos.custom_properties_permissions.reader", tags: ["perms:#{tag_value}"])
  end

  sig { params(org: Organization).void }
  def track_edit_permissions(org)
    return unless GitHub.flipper[:track_org_custom_properties_perms].enabled?

    if current_user.try(:can_have_granular_permissions?)
      via_writable_props = org.resources.organization_custom_properties.writable_by?(current_user)
      via_org_admin = org.resources.organization_administration.writable_by?(current_user)

      tag_value = if via_writable_props && via_org_admin
        "both"
      elsif via_writable_props
        "writable_props"
      else
        "org_admin"
      end

      GitHub.dogstats.increment("repos.custom_properties_permissions.values_editor", tags: ["perms:#{tag_value}"])
    end
  end
end
