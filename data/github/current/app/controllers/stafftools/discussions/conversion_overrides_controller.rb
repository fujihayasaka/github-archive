# typed: true
# frozen_string_literal: true

class Stafftools::Discussions::ConversionOverridesController < StafftoolsController
  include DiscussionsStafftoolsRoutesHelper

  before_action :ensure_repo_exists
  before_action :ensure_discussion_exists
  before_action :ensure_converting

  def create
    ConvertToDiscussionJob.perform_later(this_discussion.user, this_discussion)
    flash[:notice] = "Enqueued a new conversion job, check back in a few minutes."
    redirect_to gh_stafftools_repository_discussion_path(this_discussion)
  end

  private

  def ensure_converting
    render_404 unless this_discussion.converting?
  end
end
