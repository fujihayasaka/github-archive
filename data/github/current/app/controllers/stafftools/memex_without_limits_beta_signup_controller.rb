# typed: true
# frozen_string_literal: true

class Stafftools::MemexWithoutLimitsBetaSignupController < StafftoolsController
  RESULTS_PER_PAGE = 25
  FLAG_NAME = :memex_table_without_limits
  SAFE_QUERY_THRESHOLD = 1_000

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  preload_features [FLAG_NAME], only: [:index]

  def index
    render "stafftools/memex_without_limits_beta_signup/index", locals: {
      feature:,
      waitlist:,
    }
  end

  def create
    project = project_from_params

    check_project_exists(project)
    maybe_check_waitlist(project)
    maybe_add_to_waitlist(project)

    if params[:enable] == "1"
      maybe_check_flag(project)
      maybe_enable_project(project)
    end

    redirect_to stafftools_memex_without_limits_beta_signup_url
  end

  def update
    project = MemexProject.find_by(id: params[:project_id])

    check_project_exists(project)
    maybe_toggle_project(project)

    redirect_to stafftools_memex_without_limits_beta_signup_url
  end

  private def maybe_add_to_waitlist(project)
    return if flash[:error] # we have already detected a problem

    if project.add_to_beta_waitlist(current_user)
      flash[:notice] = "Project #{project.url} has been added to the waitlist."
    else
      flash[:error] = "Project #{project.url} could not be added to the waitlist."
    end
  end

  private def feature
    GitHub.flipper[FLAG_NAME]
  end

  private def maybe_toggle_project(project)
    return if flash[:error] # we have already detected a problem

    if feature.enabled?(project)
      maybe_disable_project(project)
    else
      maybe_enable_project(project)
    end
  end


  private def check_project_exists(project)
    return flash[:error] = "Unable to find project from #{params[:query]}." unless project
  end

  private def maybe_check_waitlist(project)
    return if flash[:error] # we have already detected a problem
    return flash[:error] = "Project #{project.url} is already on the waitlist." if EarlyAccessMembership.exists?(member: project, feature_slug: FLAG_NAME.to_s)
  end

  private def maybe_check_flag(project)
    return if flash[:error] # we have already detected a problem
    return flash[:error] = "Project #{project.url} is already flagged in." if feature.enabled?(project)
  end

  private def maybe_enable_project(project)
    return if flash[:error] # we have already detected a problem

    job_status = project.queue_reindex_items(enable_beta_flag: true)

    if job_status.error?
      flash[:error] = "There was an error kicking off the project opt-in job for #{project.url}."
    else
      flash[:notice] = "Project opt-in job kicked off for #{project.url}. It should be all set in a few minutes."
    end
  end

  private def maybe_disable_project(project)
    return if flash[:error] # we have already detected a problem

    feature.disable(project)
    flash[:notice] = "Project #{project.url} has been disabled."
  end

  private def waitlist
    safe_waitlist_members.to_a.paginate(
      page: current_page,
      per_page: params[:per_page] || RESULTS_PER_PAGE
    )
  end

  # This list could grow quite large, let's be safe and batch queries if it gets
  # big :pray:
  private def safe_waitlist_members
    lazy_query =
      EarlyAccessMembership
      .memex_without_limits_waitlist
      .includes(member: [:owner])
      .order(created_at: :desc)

    if EarlyAccessMembership.memex_without_limits_waitlist.count > SAFE_QUERY_THRESHOLD
      T.must(lazy_query.find_each)
    else
      T.must(lazy_query)
    end
  end

  # Find the memex project record by the url in the params[:query] value
  # Parsing and splitting the path of the URI given should result in something
  # like:
  # _, _owner_type, owner_login, _resource, number, ... = parsed
  private def project_from_params
    uri = Addressable::URI.parse(params[:query])
    parsed = uri.path.split("/")
    owner_login, number = parsed[2], parsed[4]

    return nil unless owner = User.find_by(login: owner_login)
    MemexProject.find_by(owner_id: owner.id, number: number.to_i)
  rescue Addressable::URI::InvalidURIError
    nil
  end
end
