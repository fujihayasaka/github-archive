# typed: true
# frozen_string_literal: true

class Stafftools::SupportPlanUploadsController < StafftoolsController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
  only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true


  def show
    render "stafftools/support_plan_uploads/index"
  end

  def update
    file = params[:file]
    return redirect_to :back unless file.present?

    dry_run = params[:dry_run] == "1"

    uploaded_file = file
    result = ::Billing::UploadSupportPlan.call(accounts_file: uploaded_file, dry_run: dry_run)

    if result[:success]
      flash.now[:notice] = result[:message]
    else
      flash.now[:error] = result[:message]
    end

    updates = result[:updates]

    render "stafftools/support_plan_uploads/index", locals: { dry_run: dry_run, updates: updates }
  end
end
