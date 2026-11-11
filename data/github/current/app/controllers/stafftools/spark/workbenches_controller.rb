# typed: true
# frozen_string_literal: true

class Stafftools::Spark::WorkbenchesController < StafftoolsController
  before_action :dotcom_required
  before_action :require_user, only: [:show, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index, :show]

  PER_PAGE = 20

  def index
    sparks = Spark::Workbench.order(created_at: :desc)
      .includes(:user)
      .paginate(page: current_page, per_page: PER_PAGE)

    render "stafftools/spark/index", locals: {
      sparks: sparks,
    }
  end

  def show
    if this_user.organization?
      this_org = this_user

      # Get paginated members first
      members = this_org.members
        .paginate(page: current_page, per_page: PER_PAGE)

      # Get spark workbench counts for these members in a separate query
      member_ids = members.map(&:id)
      workbench_counts = Spark::Workbench
        .where(user_id: member_ids)
        .group(:user_id)
        .count

      # Add spark_count attribute to each member
      members.each do |member|
        member.define_singleton_method(:spark_count) { workbench_counts[member.id] || 0 }
      end

      render "stafftools/spark/org_show", locals: {
        org: this_org,
        org_members: members,
      }, layout: "layouts/stafftools/organization/content"
    else
      user_sparks = Spark::Workbench
        .where(user: this_user)
        .order(created_at: :desc)
        .paginate(page: current_page, per_page: PER_PAGE)

      render "stafftools/spark/user_show", locals: {
        user: this_user,
        sparks: user_sparks,
        copilot_user: T.unsafe(Copilot::User).new(this_user),
      }, layout: "layouts/stafftools/user/content"
    end
  end

  def destroy
    spark = Spark::Workbench.for_uuid_string(this_user.id, params[:id])

    unless spark
      flash[:error] = "The Spark workbench could not be found."
      return redirect_to stafftools_user_spark_path(this_user)
    end

    if spark.destroy
      flash[:notice] = "The Spark workbench has been deleted."
    else
      flash[:error] = "Error deleting the Spark workbench."
    end

    redirect_to stafftools_user_spark_path(this_user)
  end

  private

  def require_user
    render_404 unless this_user
  end
end
