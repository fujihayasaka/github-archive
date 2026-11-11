# typed: true
# frozen_string_literal: true

class Businesses::OrganizationCountersController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::OrganizationCountersController#index",
  ]

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: %i(index)
  depends_on_clusters \
    ApplicationRecord::Repositories,
    optional: true,
    only: %i(index)

  def index
    keyed_contents = ActiveRecord::Base.connected_to(role: :reading) do
      keyed_objects = keyed_info_from_items(items)
      keyed_objects.each_with_object({}) do |(key, counters), contents|
        contents[key] = render_organization_table_info(counters)
      end
    end

    respond_to do |wants|
      wants.json do
        render json: keyed_contents
      end
    end
  rescue ActionController::ParameterMissing
    head :bad_request
  end

  private

  # Expects params as follows:
  #
  # params[:items] = {
  #   item-0: { organization_id: ORGANIZATION_ID },
  #   item-1: { organization_id: ORGANIZATION_ID },
  #   ...
  # }
  def items
    params.require(:items).permit!.to_h
  end

  def keyed_info_from_items(items)
    org_ids = items.values.map { |item| item[:organization_id]&.to_i }.compact.uniq
    counters_by_org_id = \
      this_business.organizations.where(id: org_ids).each_with_object({}) do |org, counters|
        counters[org.id] = {
          organization: org,
          members: org_member_count(org),
          repos: org_repo_count(org),
        }

        counters[org.id][:deploy_key_count] = org_deploy_key_count(org)
        counters[org.id][:two_factor_policy] = org_2fa_policy(org)
      end

    items.transform_values do |org_params|
      counters_by_org_id[org_params[:organization_id]&.to_i]
    end
  end

  def org_2fa_policy(org)
    return "enabled" if org.two_factor_requirement_enabled?

    "disabled"
  end

  def org_member_count(org)
    member_ids = org.member_ids
    member_count = member_ids.size
    return member_count if current_user.site_admin?
    spammy_count = User.batched_scope(:id, values: member_ids, batch_size: 10_000) { |s| s.spammy }.count
    member_count - spammy_count
  end

  def org_repo_count(org)
    with_database_error_fallback do
      org.repositories.filter_spam_for(current_user).count
    end
  end

  def org_deploy_key_count(org)
    with_database_error_fallback do
      repo_ids = org.repositories.filter_spam_for(current_user).pluck(:id)
      return 0 if repo_ids.empty?
      PublicKey.where(repository_id: repo_ids).count
    end
  end

  def render_organization_table_info(counters)
    return "" unless counters.present?

    render_to_string(
      partial: "businesses/organization_table_info",
      formats: [:html],
      locals: {
        organization: counters[:organization],
        two_factor_policy: counters[:two_factor_policy],
        members_count: counters[:members],
        repos_count: counters[:repos],
        deploy_key_count: counters[:deploy_key_count]
      }
    )
  end
end
