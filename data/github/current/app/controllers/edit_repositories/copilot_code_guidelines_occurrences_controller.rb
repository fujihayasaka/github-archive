# typed: true
# frozen_string_literal: true

class EditRepositories::CopilotCodeGuidelinesOccurrencesController < EditRepositories::AbstractCopilotCodeGuidelinesController
  include Commit::ReactDiffLinesHelper
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Copilot,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:index]

  def index
    #TODO: add has_many association to Repository model
    #todo: add pagination params to this
    unless current_repository.feature_flag_enabled?(:copilot_code_guidelines_occurrences_page, default: false)
      return head :not_found
    end
    current_guideline = Copilot::CodingGuideline.find_by(repository_id: current_repository.id, id: params[:id])
    return head :not_found unless current_guideline

    opts = {
      repository_id: current_repository.id,
      subject_type: "PullRequestReviewComment",
      copilot_coding_guideline_id: current_guideline.id,
    }
    opts[:user_feedbacks] = { feedback_type: rated_parameter } if rated_parameter.present?

    code_review_comments = PullRequests::Copilot::CodeReviewComment.
      where(opts).
      preload(subject: [:pull_request, :pull_request_review_thread]).
      includes(:user_feedbacks).
      paginate(page: params[:page], per_page: 10)

    total_count = PullRequests::Copilot::CodeReviewComment
      .where(copilot_coding_guideline_id: current_guideline.id)
      .count

    rating_counts = PullRequests::Copilot::CodeReviewComment
      .where(copilot_coding_guideline_id: current_guideline.id)
      .where.associated(:user_feedbacks)
      .includes(:user_feedbacks)
      .group(user_feedbacks: [:feedback_type])
      .count

    rating_counts["total"] = total_count

    thread_props = {}
    thread_subjects = {}
    thread_comments = {}
    diff_lines_for_code_review_comments = {}

    code_review_comments.each do |comment|
      diff_lines = comment.subject.pull_request_review_thread.prelude_diff_lines(max_context_lines: 3, cache_only: true)
      diff_line_data = diff_lines.map do |line|
        {
          type: line[:type].upcase,
          blobLineNumber: line[:type] == :deletion ? line[:left] : line[:right],
          text: line[:text],
          html: line[:html],
          position: line[:position],
          left: line[:left] == -1 ? nil : line[:left],
          right: line[:right] == -1 ? nil : line[:right],
        }
      end
      diff_lines_for_code_review_comments[comment] = diff_line_data

      thread_subjects[comment] = {
        id: comment.subject.pull_request_review_thread.global_relay_id,
        isOutdated: comment.subject.pull_request_review_thread.outdated?,
        isResolved: comment.subject.pull_request_review_thread.resolved?,
        line: comment.subject.pull_request_review_thread.line,
        path: comment.subject.pull_request_review_thread.path,
        subjectType: comment.subject.pull_request_review_thread.subject_type.upcase,
        threadPreviewComments: [], #we just care about firstComment for rendering this
        diffLines: diff_line_data,
        pullRequestId: comment.subject.pull_request.global_relay_id,
      }
      thread_comments[comment] = {
        author: {
          avatarUrl: comment.subject.user.primary_avatar_url,
          login: comment.subject.user.display_login,
          url: user_path(comment.subject.user),
        },
        authorAssociation: "NONE", # copilot has no association anyway, and also it's not getting rendered; the types just dictate it's needed
        body: comment.subject.body,
        bodyHTML: comment.subject.body_html,
        createdAt: comment.subject.created_at,
        publishedAt: comment.subject.created_at, # TODO: does this value matter?
        currentDiffResourcePath: nil, # don't think it's needed in this situation
        id: comment.subject.global_relay_id, # not sure this will actually be used but it's a required prop so let's give it the real global relay ID just in case
        databaseId: comment.subject.id,
        isHidden: false, # this is an admin view; let's just display it
        lastUserContentEdit: { # shouldn't be needed so just stubbing out
          editor: {}
        },
        repository: {
          id: comment.subject.pull_request.base_repository.global_relay_id,
          isPrivate: comment.subject.pull_request.base_repository.private?,
          name: comment.subject.pull_request.base_repository.name,
          owner: {
            id: comment.subject.pull_request.base_repository.owner.global_relay_id,
            login: comment.subject.pull_request.base_repository.owner.display_login,
            url: user_path(comment.subject.pull_request.base_repository.owner),
          },
        },
        minimizedReason: nil, #stubbing out since we're not viewing in a PR context
        reference: {
          # the associated pull request
          number: comment.subject.pull_request.number,
          author: {
            login: comment.subject.pull_request.user.display_login, # TODO: eager load this
          },
          repository: {
            id: comment.subject.pull_request.base_repository.global_relay_id,
            isPrivate: comment.subject.pull_request.base_repository.private?,
            name: comment.subject.pull_request.base_repository.name,
            owner: {
              id: comment.subject.pull_request.base_repository.owner.global_relay_id,
              login: comment.subject.pull_request.base_repository.owner.display_login,
              url: user_path(comment.subject.pull_request.base_repository.owner),
            },
          }
        },
        state: comment.subject.state.upcase, # not sure if this is needed but it's a required prop; also not sure if that's how the state is represented
        viewerCanBlockFromOrg: false, # no blocking in this context
        viewerCanMinimize: false,
        viewerCanSeeMinimizeButton: false,
        viewwerCanSeeUnminimizeButton: false,
        viewerCanReport: false,
        viewerCanReportToMaintainer: false,
        viewerCanUnblockFromOrg: false,
        viewerDidAuthor: false, # these are copilot comments; we know the viewer didn't author
        viewerRelationship: "NONE",
        url: "", # let's see if this actually is needed to render and if it's used when we render this
        viewerCanDelete: false,
        viewerCanUpdate: false,
      }
      thread_props[comment] = {
        id: comment.subject.pull_request_review_thread.id.to_s,
        viewerCanReply: false,
        commentsData: { comments: [] }, # we'll put the comment in threadSubject instead; this shouldn't actually be used in this context
        subjectType: comment.subject.pull_request_review_thread.subject_type.upcase,
      }
    end

    render "edit_repositories/copilot_code_guidelines/occurrences", locals: {
      guideline: guideline,
      paths_attributes: guideline.paths_attributes,
      code_review_comments: code_review_comments,
      diff_lines_for_code_review_comments: diff_lines_for_code_review_comments,
      thread_props:,
      thread_subjects:,
      thread_comments:,
      rated_parameter:,
      total_count:,
      filters: [
        { label: "All occurrences", icon: "pulse", href: "?", active: rated_parameter.nil? },
        { label: "Rated positive", icon: "thumbsup", href: "?rated=positive", active: rated_parameter == "positive", count: rating_counts["positive"] },
        { label: "Rated negative", icon: "thumbsdown", href: "?rated=negative", active: rated_parameter == "negative", count: rating_counts["negative"] },
      ]
    }
  end

  private

  def copilot_guideline_id
    params[:id]
  end

  def rated_parameter
    rated = request.query_parameters["rated"]
    rated if %w(positive negative).include?(rated)
  end
end
