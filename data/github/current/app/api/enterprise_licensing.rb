# typed: true
# frozen_string_literal: true

class Api::EnterpriseLicensing < Api::Enterprise::App
  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/enterprises/:enterprise_id/consumed-licenses", operation_id: "enterprise-admin/get-consumed-licenses" do
    enterprise = find_enterprise!

    control_access :read_licensing,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      resource: enterprise

    enterprise_consumed_licenses = Business::LicenseAttributer.new(enterprise).license_usage_hash(pagination: true, page: pagination[:page], per_page: pagination[:per_page])
    unless enterprise_consumed_licenses[:users].nil?
      paginator.collection_size = enterprise_consumed_licenses[:total_seats_consumed]
    end
    deliver_raw(enterprise_consumed_licenses, status: 200)
  end

  get "/enterprises/:enterprise_id/visual-studio-subscriptions", operation_id: "enterprise-admin/list-vss" do
    enterprise = find_enterprise!

    control_access :standard_authorization,
      resource: enterprise,
      permission: :read_enterprise_licensing,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    rel = enterprise.bundled_license_assignments.nonrevoked

    if params["is_unmatched_only"].present? && params["is_unmatched_only"] == "true"
      rel = rel.where(user: nil)
    end

    visual_studio_subscription_assignments = paginate_rel(rel)

    deliver :visual_studio_subscription_assignments_hash, { visual_studio_subscription_assignments: visual_studio_subscription_assignments, total_count: visual_studio_subscription_assignments.total_entries }
  end

  put "/enterprises/:enterprise_id/visual-studio-subscriptions/:visual_studio_subscription_id", read_from_replicas: true, operation_id: "enterprise-admin/update-vss-manual-match" do
    enterprise = find_enterprise!

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_licensing,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    unless data["user_identifier"].present?
      deliver_error! 422, { message: "user_identifier is required" }
    end

    user = User.find_by_login_or_email(data["user_identifier"].to_s)

    unless user
      deliver_error! 404, { message: "User not found" }
    end

    bua = enterprise.user_accounts.find_by(user: user)
    unless bua
      # Return user not found so someone can't use this endpoint to fish for users by email
      deliver_error! 404, { message: "User not found" }
    end

    bla = enterprise.bundled_license_assignments.nonrevoked.with_subscription(params[:visual_studio_subscription_id]).first
    unless bla
      deliver_error! 404, { message: "Visual Studio subscription not found" }
    end

    if bla.user_id.present? && !bla.manual_match
      deliver_error! 422, { message: "Visual Studio subscription was already matched to a user automatically" }
    end

    bla.user = user
    bla.manual_match = true

    with_write do
      if bla.save
        deliver :visual_studio_subscription_assignment_hash, bla, status: 200
      else
        deliver_error 422,
          errors: bla.errors,
          documentation_url: @documentation_url
      end
    end
  end

  delete "/enterprises/:enterprise_id/visual-studio-subscriptions/:visual_studio_subscription_id", read_from_replicas: true, operation_id: "enterprise-admin/delete-vss-manual-match" do
    enterprise = find_enterprise!

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_licensing,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    bla = enterprise.bundled_license_assignments.nonrevoked.with_subscription(params[:visual_studio_subscription_id]).first
    unless bla
      deliver_error! 404, { message: "Visual Studio subscription not found" }
    end

    if bla.user_id.present? && !bla.manual_match
      deliver_error! 422, { message: "Visual Studio subscription was matched to a user automatically and cannot be unassigned" }
    end

    bla.user = nil
    bla.manual_match = false
    with_write do
      if bla.save
        deliver :visual_studio_subscription_assignment_hash, bla, status: 200
      else
        deliver_error 422,
          errors: bla.errors,
          documentation_url: @documentation_url
      end
    end
  end
end
