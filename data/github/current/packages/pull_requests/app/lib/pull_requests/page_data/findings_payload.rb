# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  class FindingsPayload
    extend GitHub::ResilienceMixin

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(User),
      ).returns(T::Hash[String, T.untyped])
    end
    def self.build(pull_request:, current_user: nil)
      new(pull_request:, current_user:).build
    end

    sig { params(pull_request: PullRequest).returns(Integer) }
    def self.count(pull_request:)
      with_database_error_fallback(fallback: 0) do
        new(pull_request:).count
      end
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(User)).void }
    def initialize(pull_request:, current_user: nil)
      @pull_request = T.let(pull_request, PullRequest)
      @repository = T.let(T.must(pull_request.repository), Repository)
      @current_user = T.let(current_user, T.nilable(User))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def build
      check_annotations = annotations_query.to_a

      cs_results = code_scanning_results(check_annotations)

      annotation_findings = check_annotations
        .map do |a|
          {
            "entityType" => "annotation",
            "entity" => serialize_annotation(a, cs_results[a.id]),
          }
        end

      automated_review_comment_findings = @pull_request.automated_review_comments
        .map do |arc|
          {
            "entityType" => "automated_review_comment",
            "entity" => serialize_automated_review_comment(arc),
          }
        end

      {
        "findings" => annotation_findings + automated_review_comment_findings,
        "mergeReadiness" => merge_readiness_comment,
        "overviewSummary" => render_markdown(overview_summary),
        "pullRequestBasePath" => @pull_request.path_uri.to_s,
        "pullRequestStoreData" => serialize_pull_request_store_data,
        "ignoredEntityIds" => ignored_entity_ids,
      }
    end

    sig { returns(Integer) }
    def count
      annotations_query.count + @pull_request.automated_review_comments.count
    end

    private

    sig { returns(T::Hash[String, T.untyped]) }
    def serialize_pull_request_store_data
      pr_state = if @pull_request.merged?
        "MERGED"
      elsif @pull_request.closed?
        "CLOSED"
      elsif @pull_request.draft?
        "DRAFT"
      else
        "OPEN"
      end

      {
        "comparison" => {
          "baseOid" => @pull_request.base_sha,
          "headOid" => @pull_request.head_sha,
        },
        "pullRequestId" => @pull_request.id.to_s,
        "pullRequestNumber" => @pull_request.number,
        "pullRequestState" => pr_state,
        "authorLogin" => @pull_request.user&.display_login || "",
        "repositoryId" => @repository.id,
      }
    end

    sig { returns(T.untyped) }
    def annotations_query
      @repository.annotations_for(sha: @pull_request.head_sha, limit: CheckAnnotation::MAX_READ_LIMIT)
        .includes(:code_scanning_annotation, :dependabot_annotation, :check_run)
    end

    sig { returns(T::Array[String]) }
    def ignored_entity_ids

      kv = PullRequests::KV.for_repository(@repository)
      key = "pull_requests/code_review_findings/ignored/pr#{@pull_request.number}"
      json = kv.get(key).value { nil }
      return [] if json.nil?

      Array(JSON.parse(json))
    rescue JSON::ParserError
      []
    end

    sig { params(annotation: CheckAnnotation).returns(String) }
    def annotation_source(annotation)
      if annotation.code_scanning_annotation.present?
        "code_scanning"
      elsif annotation.dependabot_annotation.present?
        "dependabot"
      else
        "general"
      end
    end

    sig { params(annotation: CheckAnnotation).returns(T.nilable(String)) }
    def annotation_tool_name(annotation)
      annotation.check_run&.code_scanning_tool_name
    end

    sig { params(annotations: T::Array[CheckAnnotation]).returns(T::Hash[Integer, T::Hash[String, T.untyped]]) }
    def code_scanning_results(annotations)
      cs_annotations = annotations.select { |a| a.code_scanning_annotation.present? }
      return {} if cs_annotations.empty?

      results_by_id = CodeScanningAnnotation.results_by_id(repository: @repository, annotations: cs_annotations)
      alert_numbers = cs_annotations.filter_map { |a| a.code_scanning_annotation&.alert_number }
      suggested_fixes = fetch_suggested_fixes(alert_numbers)

      results_by_id.transform_values do |result_data|
        result = result_data[:result]
        next nil if result.nil?

        proto_result = result.result
        rule = proto_result&.rule
        alert_number = proto_result&.number
        fix_alert = suggested_fixes[alert_number]

        {
          "alertNumber" => alert_number,
          "ruleSarifId" => rule&.sarif_identifier,
          "ruleName" => rule&.name,
          "ruleDescription" => rule&.short_description,
          "ruleFullDescription" => rule&.full_description,
          "ruleHelp" => rule&.help,
          "ruleHelpUri" => rule&.help_uri,
          "ruleTags" => rule&.tags&.to_a,
          "ruleSeverity" => proto_result&.rule_severity&.to_s.downcase,
          "securitySeverity" => proto_result&.security_severity&.to_s,
          "messageText" => proto_result&.message_text,
          "messageMarkdown" => proto_result&.message_markdown,
          "messageHtml" => render_markdown(proto_result&.message_markdown || proto_result&.message_text),
          "hasCodePaths" => result.has_code_paths || false,
          "classifications" => proto_result&.most_recent_instance&.classification&.to_a,
          "suggestedFix" => serialize_suggested_fix(fix_alert),
          "suggestedFixDescriptionHtml" => render_markdown(fix_alert&.suggested_fix&.description),
        }
      end
    end

    sig { params(alert_numbers: T::Array[Integer]).returns(T::Hash[Integer, T.untyped]) }
    def fetch_suggested_fixes(alert_numbers)
      return {} if alert_numbers.empty?

      @pull_request.async_preload_code_scanning_suggested_fixes
      alert_numbers.each_with_object({}) do |number, hash|
        fix_alert = @pull_request.code_scanning_suggested_fix_alert(number)
        hash[number] = fix_alert if fix_alert.present?
      end
    end

    sig { params(fix_alert: T.untyped).returns(T.nilable(T::Hash[String, T.untyped])) }
    def serialize_suggested_fix(fix_alert)
      return nil if fix_alert.nil?

      fix = fix_alert.suggested_fix
      return nil if fix.nil?

      {
        "state" => fix_alert.state&.to_s,
        "description" => fix.description,
        "outdated" => fix.outdated || false,
        "files" => fix.files&.map do |file|
          {
            "filePath" => file.file_path,
            "diffContent" => file.diff_content&.dup&.force_encoding("UTF-8"),
          }
        end || [],
        "dependencyMetadata" => fix.dependency_metadata&.map do |dep|
          {
            "name" => dep.name,
            "version" => dep.version,
          }
        end || [],
      }
    end

    sig { params(annotation: CheckAnnotation, cs_result: T.nilable(T::Hash[String, T.untyped])).returns(T::Hash[String, T.untyped]) }
    def serialize_annotation(annotation, cs_result = nil)
      {
        "id" => annotation.id,
        "source" => annotation_source(annotation),
        "toolName" => annotation_tool_name(annotation),
        "filename" => annotation.filename,
        "startLine" => annotation.start_line,
        "endLine" => annotation.end_line,
        "startColumn" => annotation.start_column,
        "endColumn" => annotation.end_column,
        "annotationLevel" => annotation.annotation_level, # e.g. "failure", "warning", "notice"
        "title" => annotation.title,
        "message" => annotation.message,
        "suggestedChange" => annotation.suggested_change,
        "codeScanningDetails" => cs_result,
      }
    end

    sig { params(arc: AutomatedReviewComment).returns(T::Hash[String, T.untyped]) }
    def serialize_automated_review_comment(arc)
      review_comment = arc.pull_request_review_comment
      message_html = render_markdown(arc.message)
      {
        "id" => arc.id,
        "pullRequestReviewCommentId" => review_comment&.id,
        "source" => arc.source.delete_prefix("source_"),
        "severity" => arc.severity.delete_prefix("severity_"),
        "securitySeverity" => arc.security_severity.delete_prefix("security_severity_"),
        "title" => arc.title || arc.message.truncate(65, separator: " "),
        "message" => arc.message,
        "messageHtml" => message_html,
        "suggestionState" => arc.suggestion_state.delete_prefix("suggestion_state_"),
        "fixed" => arc.fixed?,
        "dismissed" => arc.dismissed?,
        "path" => T.unsafe(review_comment)&.path,
        "line" => T.unsafe(review_comment)&.original_position,
        "body" => review_comment&.body,
        "suggestion" => serialize_arc_suggestion(arc),
        "comment" => serialize_arc_as_comment(arc, review_comment, message_html),
      }
    end

    PR_OVERVIEW_HEADER = T.let("## Pull request overview".freeze, String)

    sig { returns(T.nilable(String)) }
    def overview_summary
      bot = Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot

      return nil if bot.nil?

      review = @pull_request.reviews.where(user_id: bot.id).order(created_at: :desc).first
      return nil if review.nil?

      body = review.body
      return nil if body.blank?

      header_index = body.index(PR_OVERVIEW_HEADER)
      return nil if header_index.nil?

      content_start = header_index + PR_OVERVIEW_HEADER.length
      next_section_index = body.index(/^###\s|^<details/m, content_start)

      summary_text = if next_section_index
        body[content_start...next_section_index]
      else
        body[content_start..]
      end

      summary_text&.strip.presence
    end

    MERGE_READINESS_PATTERNS = T.let({
      "Copilot thinks this PR is ready to approve and merge." => "ready",
      "Copilot thinks this PR is not ready to merge" => "needs_changes",
      "too complex or risky for Copilot to approve" => "too_complex",
    }.freeze, T::Hash[String, String])

    sig { returns(T.nilable(String)) }
    def merge_readiness_comment
      app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
      return nil if app.nil?

      bot = app.bot
      return nil if bot.nil?

      issue = @pull_request.issue
      return nil if issue.nil?

      comment = issue.comments.where(user_id: bot.id).order(created_at: :desc).first
      return nil if comment.nil?

      body = comment.body
      return nil if body.blank?

      MERGE_READINESS_PATTERNS.each do |pattern, intent|
        return intent if body.include?(pattern)
      end

      nil
    end

    sig { params(text: T.nilable(String)).returns(T.nilable(String)) }
    def render_markdown(text)
      return nil if text.blank?

      GitHub::Goomba::MarkdownPipeline.to_html(text)
    end

    sig { params(arc: AutomatedReviewComment).returns(T.nilable(T::Hash[String, T.untyped])) }
    def serialize_arc_suggestion(arc)
      suggestion = arc.suggestion
      return nil if suggestion.nil?

      {
        "commitSha" => suggestion.commit_sha,
        "files" => suggestion.files.map do |file|
          {
            "path" => file.path,
            "diffContent" => file.diff_content.dup.force_encoding("UTF-8"),
          }
        end,
      }
    end

    sig { params(arc: AutomatedReviewComment, review_comment: T.untyped, message_html: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def serialize_arc_as_comment(arc, review_comment, message_html)
      author = T.unsafe(review_comment)&.user

      suggestion_props = build_arc_suggestion_props(arc)

      {
        "author" => {
          "id" => author&.id.to_s,
          "login" => author&.display_login || "copilot-pull-request-reviewer[bot]",
          "avatarUrl" => author&.primary_avatar_url || "",
        },
        "authorAssociation" => "NONE",
        "automatedComment" => {
          "id" => arc.id.to_s,
          "title" => arc.title,
          "message" => message_html,
          "severity" => arc.severity.delete_prefix("severity_"),
          "securitySeverity" => arc.security_severity.delete_prefix("security_severity_"),
          "source" => arc.source.delete_prefix("source_"),
          "suggestionState" => suggestion_props[:suggestion_state],
          "suggestion" => suggestion_props[:suggestion],
          "feedbackOptions" => arc.feedback_options,
          "showFeedbackButtons" => arc.show_feedback_buttons?,
          "showAiNote" => arc.show_ai_note?,
          "dismissable" => arc.dismissable?,
          "delegatedDismissalEnabled" => arc.delegated_dismissal_enabled?,
          "dismissalOptions" => arc.dismissal_options,
          "isDismissed" => arc.dismissed?,
          "isFixed" => arc.fixed?,
          "dismissalReason" => arc.dismissal_reason,
          "dismissedBy" => arc.dismissed_by,
          "viewerCanDismiss" => @current_user.present? && arc.can_dismiss?(user: @current_user),
          "viewerCanReopen" => @current_user.present? && arc.can_reopen?(user: @current_user),
        },
        "body" => review_comment&.body || arc.message,
        "bodyHTML" => message_html || "",
        "createdAt" => review_comment&.created_at&.iso8601 || "",
        "publishedAt" => review_comment&.created_at&.iso8601,
        "databaseId" => review_comment&.id,
        "id" => review_comment&.global_relay_id || arc.id.to_s,
        "isHidden" => false,
        "lastUserContentEdit" => nil,
        "minimizedReason" => nil,
        "reactionGroups" => [],
        "reference" => {
          "number" => @pull_request.number,
          "author" => { "login" => @pull_request.user&.display_login },
          "text" => nil,
        },
        "repository" => {
          "id" => @repository.id.to_s,
          "isPrivate" => @repository.private?,
          "name" => @repository.name,
          "owner" => {
            "id" => @repository.owner&.id.to_s,
            "login" => @repository.owner&.display_login,
          },
        },
        "reviewVariantType" => "automated",
        "state" => "submitted",
        "url" => review_comment&.url || "",
        "viewerCanBlockFromOrg" => false,
        "viewerCanMinimize" => false,
        "viewerCanUnminimize" => false,
        "viewerCanSeeMinimizeButton" => false,
        "viewerCanSeeUnminimizeButton" => false,
        "viewerCanReact" => false,
        "viewerCanReport" => false,
        "viewerCanReportToMaintainer" => false,
        "viewerCanUnblockFromOrg" => false,
        "viewerDidAuthor" => false,
        "viewerRelationship" => "none",
        "viewerCanDelete" => false,
        "viewerCanUpdate" => false,
      }
    end

    sig { params(arc: AutomatedReviewComment).returns({ suggestion_state: String, suggestion: T.nilable(T::Hash[String, T.untyped]) }) }
    def build_arc_suggestion_props(arc)
      suggestion_state = arc.suggestion_state
      formatted_state = suggestion_state.delete_prefix("suggestion_state_")

      if suggestion_state.in?(%w[
        suggestion_state_no_suggestion
        suggestion_state_pending
        suggestion_state_error
      ])
        return { suggestion_state: formatted_state, suggestion: nil }
      end

      begin
        diff_entries_payload = arc.suggestion&.diff_entries_payload
      rescue ::ReviewComments::Suggestion::ParseError => e
        Failbot.report!(e)
      end

      return { suggestion_state: "error", suggestion: nil } if diff_entries_payload.blank?

      {
        suggestion_state: formatted_state,
        suggestion: { "diffEntries" => diff_entries_payload },
      }
    end
  end
end
