# typed: true
# frozen_string_literal: true

class Stafftools::BulkDmcaTakedownController < StafftoolsController
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:validate_repos]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:parse_notice]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :validate_repos],
    optional: true

  # Form for uploading text of dmca take down notice
  def parse_notice # rubocop:todo GitHub/UseRestfulActions
    notice = Stafftools::BulkDmcaTakedown::Notice.new
    render "stafftools/bulk_dmca_takedown/parse_notice", locals:
      { notice: notice }
  end

  # Lists out the repos found in a notice and allows
  # user to select the repos to be taken down
  def new
    notice = Stafftools::BulkDmcaTakedown::Notice.new(parser_params)

    if notice.valid?
      bulk_dmca_takedown = Stafftools::BulkDmcaTakedown.from_notice(notice, current_user)
      if bulk_dmca_takedown.save
        return redirect_to stafftools_bulk_dmca_takedown_validate_repos_path(bulk_dmca_takedown)
      end
    end

    flash[:error] = "Unable to create takedown"
    render "stafftools/bulk_dmca_takedown/parse_notice", locals: { notice: notice }
  end

  def validate_repos # rubocop:todo GitHub/UseRestfulActions
    bulk_dmca_takedown = Stafftools::BulkDmcaTakedown.not_started.find(params["id"])
    render "stafftools/bulk_dmca_takedown/validate_repos", locals: { bulk_dmca_takedown: bulk_dmca_takedown }
  end

  # Creates the job that takes down the repos
  def start_job # rubocop:todo GitHub/UseRestfulActions
    bulk_dmca_takedown = Stafftools::BulkDmcaTakedown.find(params["id"])

    if params["stafftools_bulk_dmca_takedown"]["repository_ids"].nil?
      flash[:error] = "No repositories are selected for takedown"
      render "stafftools/bulk_dmca_takedown/validate_repos", locals: { bulk_dmca_takedown: bulk_dmca_takedown }
    else
      bulk_dmca_takedown.assign_attributes(new_params)
      bulk_dmca_takedown.disabling_user = current_user
      if bulk_dmca_takedown.save
        bulk_dmca_takedown.execute
        redirect_to stafftools_bulk_dmca_takedown_path(bulk_dmca_takedown)
      else
        render "stafftools/bulk_dmca_takedown/validate_repos", locals: { bulk_dmca_takedown: bulk_dmca_takedown }
      end
    end
  end

  # Shows the status of the takedown job
  def show
    bulk_dmca_takedown = Stafftools::BulkDmcaTakedown.includes(:repositories).find(params["id"])
    render "stafftools/bulk_dmca_takedown/show", locals: { bulk_dmca_takedown: bulk_dmca_takedown }
  end

  def index
    render "stafftools/bulk_dmca_takedown/index", locals: { bulk_dmca_takedowns: Stafftools::BulkDmcaTakedown.order(created_at: :desc).paginate(page: params[:page]) }
  end

  private

  def parser_params
    params.required(:stafftools_bulk_dmca_takedown_notice).permit(:notice_text, :public_url)
  end

  def new_params
    params.required(:stafftools_bulk_dmca_takedown).permit(:notice_public_url, repository_ids: [])
  end
end
