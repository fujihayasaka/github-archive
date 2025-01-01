# typed: true
# frozen_string_literal: true

class Stafftools::ReviewCommentsController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :ensure_issue_exists, only: [:index, :first]
  before_action :ensure_comment_exists, only: [:show, :database]

  layout "layouts/stafftools/repository/collaboration"

  def index
    review_comments = this_pull.review_comments.paginate \
      page: params[:page] || 1,
      per_page: 25
    render "stafftools/review_comments/index", locals: { review_comments: review_comments }
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/review_comments/database"
  end

  def show
    render "stafftools/review_comments/show"
  end

  private

  memoize def this_comment
    this_pull.review_comments.find_by_id(params[:id])
  end
  helper_method :this_comment

  def this_pull
    this_issue.pull_request
  end
  helper_method :this_pull

  def ensure_comment_exists
    return render_404 if this_comment.nil?
  end

end
