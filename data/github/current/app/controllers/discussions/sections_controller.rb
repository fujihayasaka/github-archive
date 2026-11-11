# typed: true
# frozen_string_literal: true

class Discussions::SectionsController < Discussions::BaseController
  before_action :login_required, only: [:new, :create, :edit, :update, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex, only: [:new, :edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:edit, :new],
    optional: true

  def new
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to new_org_discussions_section_path(current_repository.owner)
    end

    return render_404 unless current_user.can_create_discussion_category?(current_repository)

    render "discussion_sections/new", locals: { section: current_repository.discussion_sections.build }
  end

  def create
    return render_404 unless current_user.can_create_discussion_category?(current_repository)

    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    new_section = current_repository.discussion_sections.build(
      name: section_params[:name],
      emoji: section_params[:emoji],
      discussion_category_ids: section_params[:category_ids]
    )

    if new_section.save
      flash[:notice] = "Section \"#{new_section.name}\" has been created."
      redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
    else
      render "discussion_sections/new", locals: { section: new_section }
    end
  end

  def edit
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    if current_repository.organization_discussion.present? && !is_org_level?
      return redirect_to new_org_discussions_section_path(current_repository.owner)
    end

    return render_404 unless current_user.can_create_discussion_category?(current_repository)
    render "discussion_sections/edit", locals: { section: section }
  end

  def update
    return render_404 unless current_user.can_create_discussion_category?(current_repository)

    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    if section.update(
      name: section_params[:name],
      emoji: section_params[:emoji],
      discussion_category_ids: section_params[:category_ids]
    )
      flash[:notice] = "Section \"#{section.name}\" has been updated."
      redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
    else
      render "discussion_sections/edit", locals: { section: section }
    end
  end

  def destroy
    return render_404 unless current_user.can_create_discussion_category?(current_repository)

    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }

    if section.destroy
      flash[:notice] = "Section \"#{section.name}\" has been deleted."
    else
      flash[:error] = "Could not delete section \"#{section.name}\" at this time."
    end

    redirect_to agnostic_categories_path(repository: current_repository, org_param: org_param)
  end

  private

  def section_params
    params.require(:section).permit(:name, :emoji, :all_categories, category_ids: [])
  end

  memoize def section
    current_repository = T.must_because(self.current_repository) { "#ask_the_gatekeeper ensures non-nil" }
    current_repository.discussion_sections.find_by!(slug: params[:slug])
  end
end
