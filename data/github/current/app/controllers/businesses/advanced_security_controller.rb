# typed: true
# frozen_string_literal: true

class Businesses::AdvancedSecurityController < Businesses::BusinessController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:advanced_security_orgs_list, :advanced_security_users_list]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:advanced_security_orgs_list],
    optional: true

  # These access restrictions aim to match those from Businesses::LicensesController
  # when on GHES, or Businesses::BillingSettingsController when on dotcom.
  before_action :business_owner_required if GitHub.enterprise?
  before_action :business_access_required if !GitHub.enterprise?
  before_action :business_not_downgraded_to_free_plan_required

  track_latency_slo "p99-ui-request", 5000, only: [:advanced_security_orgs_list, :advanced_security_users_list]
  track_latency_slo "p50-ui-request", 500, only: [:advanced_security_orgs_list, :advanced_security_users_list]
  track_availability_slo "ui-request", only: [:advanced_security_orgs_list, :advanced_security_users_list]

  def advanced_security_users_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    current_page = params[:page].to_i
    current_page = 1 if current_page == 0
    page_size = 10

    start = GitHub::Dogstats.monotonic_time
    users_and_counts = this_business.get_advanced_security_enterprise_users_and_counts(actor: current_user, page: current_page - 1, page_size: page_size)
    elapsed = GitHub::Dogstats.duration(start)
    if elapsed > 2000
      # Log slow cases
      GitHub.logger.info(
        "Slow org and count computation",
        "code.namespace" => "Businesses::AdvancedSecurityController",
        "code.function" => "advanced_security_orgs_list",
        "gh.business.id" => this_business&.id,
        "gh.business.slug" => this_business&.slug,
        "time.elapsed" => elapsed
      )
    end

    users = WillPaginate::Collection.create(current_page, page_size, users_and_counts[:count]) do |pager|
      pager.replace(users_and_counts[:users])
    end

    first_user_index = (current_page - 1) * page_size + 1

    render partial: "businesses/billing_settings/advanced_security_user_list", locals: {
      users: users,
      first_user_index: first_user_index,
      last_user_index: first_user_index + users.length - 1,
      total_users_count: users_and_counts[:count],
      num_user_users_without_ghas: users_and_counts[:num_without_ghas],
      hide_pagination: users_and_counts[:count] <= page_size,
      link_renderer: AdvancedSecurityUsersLinkRenderer,
    }
  end

  def advanced_security_orgs_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless this_business.advanced_security_purchased?

    current_page = params[:page].to_i
    current_page = 1 if current_page == 0
    page_size = 10

    start = GitHub::Dogstats.monotonic_time
    orgs_and_counts = this_business.get_advanced_security_orgs_and_counts(page: current_page - 1, page_size: page_size)
    elapsed = GitHub::Dogstats.duration(start)
    if elapsed > 2000
      # Log slow cases
      GitHub.logger.info(
        "Slow org and count computation",
        "code.namespace" => "Businesses::AdvancedSecurityController",
        "code.function" => "advanced_security_orgs_list",
        "gh.business.id" => this_business&.id,
        "gh.business.slug" => this_business&.slug,
        "time.elapsed" => elapsed
        )
    end

    orgs = WillPaginate::Collection.create(current_page, page_size, orgs_and_counts[:total_orgs_count]) do |pager|
      pager.replace(orgs_and_counts[:orgs])
    end

    first_org_index = (current_page - 1) * page_size + 1

    render partial: "businesses/billing_settings/advanced_security_org_list", locals: {
      orgs: orgs,
      first_org_index: first_org_index,
      last_org_index: first_org_index + orgs.length - 1,
      total_orgs_count: orgs_and_counts[:total_orgs_count],
      num_orgs_without_ghas: orgs_and_counts[:num_orgs_without_ghas],
      hide_pagination: orgs_and_counts[:total_orgs_count] <= page_size,
      link_renderer: AdvancedSecurityEntitiesLinkRenderer,
    }
  end
end
