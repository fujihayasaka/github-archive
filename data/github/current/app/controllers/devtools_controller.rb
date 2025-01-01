# typed: true
# frozen_string_literal: true

class DevtoolsController < ApplicationController

  before_action :push_failbot_metadata
  before_action :dotcom_required
  before_action :require_admin_frontend
  before_action :devtools_only
  # CAP bypass is fine as dotcom_required in Proxima.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  layout "layouts/devtools"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:restricted]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    set_nav_breadcrumb ContextRegion::DevtoolsCrumb.new
    render "devtools/index"
  end

  def restricted # rubocop:todo GitHub/UseRestfulActions
    flash[:notice] = "Redirected you to #{GitHub.admin_host_name} and… You made it through! Congrats! 🥳"
    render "devtools/index"
  end

  def bounce # rubocop:todo GitHub/UseRestfulActions
    redirect_to "/devtools/#{params[:section]}/#{params[:args].join '/'}"
  end


  protected

  def push_failbot_metadata
    Failbot.push(devtools: true)
  end

  # before_action to restrict access to GitHub developers only
  #
  # Throws a 404 if the current user is not GitHub developer.
  # Redirect to employees to JIT
  def devtools_only
    return if github_developer? || site_admin?
    redirect_jit_for_employees
  end
end
