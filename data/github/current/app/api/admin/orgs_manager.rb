# typed: true
# frozen_string_literal: true

class Api::Admin::OrgsManager < Api::Admin

  before do
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?
  end

  # Create an organization
  post "/admin/organizations", operation_id: "enterprise-admin/create-org" do # rubocop:todo GitHub/ControlAccess
    data = receive_with_schema("organization", "create")

    admin_user = User.find_by_login(data["admin"])
    deliver_error! 422, message: "Admin user could not be found" unless admin_user.present?

    begin
      result = Organization::Creator.perform \
        admin_user,
        GitHub::Plan.default_plan,
        { login: data["login"] }
      org = result.organization

      if result.success?
        org.update profile_name: data["profile_name"]
        deliver :organization_hash, org, status: 201
      else
        if result.error_message.present?
          deliver_error 422, message: result.error_message
        else
          deliver_error 422, errors: org.errors
        end
      end
    rescue # rubocop:todo Lint/GenericRescue
      deliver_error 422, errors: "Could not create organization #{data['login']}."
    end
  end

  # Rename an organization
  # rubocop:todo GitHub/ControlAccess
  patch "/admin/organization/:org_id", operation_id: "enterprise-admin/update-org-name" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    rename_org
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/organization/:org_id", operation_id: :deprecated do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    rename_org
  end
  # rubocop:enable GitHub/ControlAccess

  private

  def rename_org
    org = find_org!
    deliver_error!(404) if org.trusted_oauth_apps_owner?

    data = receive(Hash)
    attributes = attr(data, :login)
    if org.rename(attributes[:login])
      message = "Job queued to rename organization. It may take a few minutes to complete."
      url     = api_url("/organizations/#{org.id}")
      response["location"] = url
      deliver_raw(
        {
          message: message,
          url: url,
        },
        status: 202,
      )
    else
      deliver_error! 422, errors: org.errors
    end
  end
end
