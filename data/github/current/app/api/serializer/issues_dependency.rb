# typed: true
# frozen_string_literal: true

module Api::Serializer::IssuesDependency
  PUBLIC_VISIBILITY_ORGANIZATION_MEMBERS_ONLY = "organization_members_only".freeze
  INTERNAL_VISIBILITY_ORG_ONLY = "org_only".freeze

  extend T::Helpers
  include GitHub::Tracing

  requires_ancestor { Api::Serializer::UserDependency }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  class UnsupportedCrossReferenceSource < RuntimeError
    def initialize(source)
      super "Unsupported CrossReference source: #{source.class.name}"
    end
  end

  trace_method :issue_comment_hash
  def issue_comment_hash(comment, options = {})
    return nil if !comment
    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, comment)
    issue = options[:issue] || comment.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    hash = {
      url: url("/repos/#{repo}/issues/comments/#{comment.id}", options),
      html_url: comment.permalink, # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue_url: url("/repos/#{repo}/issues/#{issue.try(:number)}", options),
      id: comment.id,
      node_id: global_id_for(comment, options),
      user: T.unsafe(self).user_hash(comment.safe_user, content_options(options)),
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
    }.update(mime_body_hash(comment, options))

    unless options[:skip_author_association]
      association = comment
        .author_association_symbol(options[:current_user] || options[:author_association_viewer])
        .to_s
        .upcase
      hash[:author_association] = association
    end

    unless issue.pull_request?
      hash[:pin] = pinned_issue_comment_hash(comment.pinned_issue_comment, options)
    end

    hash[:reactions] = T.unsafe(self).reactions_rollup(comment, url("/repos/#{repo}/issues/comments/#{comment.id}/reactions", options))
    hash[:performed_via_github_app] = T.unsafe(self).integration_hash(comment.performed_via_integration, options)

    hash
  end

  PinnableFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Pinnable {
      isPinned
      pinnedAt
      pinnedBy {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }
    }
  GRAPHQL

  IssueCommentFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on IssueComment {
      url
      id
      createdAt
      updatedAt

      issue {
        number
      }

      repository {
        nameWithOwner
      }

      authorAssociation

      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }

      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment

      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment

      ...Api::Serializer::IssuesDependency::PinnableFragment

      viaApp {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragment @include(if: $includePerformedViaGitHubApp)
      }
    }
  GRAPHQL

  def graphql_issue_comment_hash(comment, options = {})
    options = Api::SerializerOptions.from(options)
    comment = Api::Serializer::IssuesDependency::IssueCommentFragment.new(comment)
    return unless comment

    # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
    repo    = comment.repository.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner

    database_id = model_id_for_global_id(comment.id)

    author_hash = if comment.author.present?
      graphql_simple_user_hash(comment.author, content_options(options))
    else
      simple_user_hash(User.ghost, content_options(options))
    end

    hash = {
      url: url("/repos/#{repo}/issues/comments/#{database_id}", options),
      html_url: comment.url.to_s,
      issue_url: url("/repos/#{repo}/issues/#{comment.issue&.number}", options),
      id: database_id,
      node_id: comment.id,
      user: author_hash,
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      author_association: comment.author_association,
    }.update(graphql_mime_body_hash(comment, options))

    hash[:reactions] = graphql_reactions_rollup(comment, url("/repos/#{repo}/issues/comments/#{database_id}/reactions", options))
    hash[:performed_via_github_app] = graphql_integration_hash(comment.via_app, options)

    # Check if isPinned is present in the raw GraphQL response data (the field is conditionally included via @include directive)
    comment_hash = comment.to_h
    if comment_hash.key?("isPinned")
      pinnable_fragment = Api::Serializer::IssuesDependency::PinnableFragment.new(comment)
      hash[:pin] = graphql_pinned_issue_comment_hash(pinnable_fragment, options)
    end

    hash
  end

  def pull_request_review_thread_hash(item, options = {})
    {
      node_id: global_id_for(item, options),
      comments: item.comments.map { |comment| pull_request_review_comment_hash(comment, options) },
    }
  end

  def commit_comment_thread_hash(item, options = {})
    {
      node_id: global_id_for(item, options),
      commit_id: item.comments.first.commit_id,
      comments: item.comments.map { |comment| commit_comment_hash(comment, options) },
    }
  end

  def pinned_issue_comment_hash(pinnable, options = {})
    return unless pinnable

    {
      pinned_by: T.unsafe(self).user_hash(pinnable.safe_pinned_by, content_options(options)),
      pinned_at: time(pinnable.created_at),
    }
  end

  def graphql_pinned_issue_comment_hash(pinnable, options = {})
    return unless pinnable
    return unless !pinnable.respond_to?(:is_pinned?) || pinnable.is_pinned?

    {
      pinned_by: graphql_simple_user_hash(pinnable.pinned_by, content_options(options)),
      pinned_at: time(pinnable.pinned_at),
    }
  end

  trace_method :cross_reference_hash
  def cross_reference_hash(ref, options = {})
    xref_hash = {
      actor: user_hash(ref.actor, content_options(options)),
      created_at: time(ref.created_at),
      updated_at: time(ref.updated_at),
    }

    # CrossReferences are polymorphic, all supported source types must
    # be handled here.
    xref_hash[:source] = { type: ref.source_type.downcase }
    case ref.source
    when Issue
      # Nulling out options.repo so that the repo path will be deduced from the *referencing* issue
      xref_hash[:source][:issue] = issue_hash(ref.source, options.merge({ repositories: true, repo: nil }))
    else
      error = UnsupportedCrossReferenceSource.new(ref.source)
      error.set_backtrace(caller)
      Failbot.report(error, source: ref.source)
    end

    xref_hash
  end

  trace_method :search_label_hash
  def search_label_hash(label_result, options = {})
    label = label_result["_model"]
    return unless label

    label_hash(label, options)
  end

  trace_method :issue_timeline_hash
  def issue_timeline_hash(item, options = {})
    options = Api::SerializerOptions.from(options)

    case item
    when IssueComment
      event_hash = issue_comment_hash(item, options)

      event_hash[:event] = "commented"

      # TODO: remove :user from the event hash before preview ends. We
      # are sending both during preview to not break existing clients
      # that expect :user.
      event_hash[:actor] = event_hash[:user]

      event_hash
    when IssueEvent
      event_hash = issue_event_hash(item, options)

      # Fix up the assigner/assignee for (un)assigned events. The actor and subject
      # are switched in issue events, and changing them in the event hash would break
      # the events API - but the timeline API can return them as expected.
      if item.assigned? || item.unassigned?
        event_hash[:actor] = event_hash.delete(:assigner)
      end

      event_hash
    when CrossReference
      cross_reference_hash(item, options).merge(event: "cross-referenced")
    when Platform::Models::PullRequestCommit
      commit_hash(item.commit, options).merge(event: "committed")
    when PullRequestReview
      pull_request_review_hash(item, options).merge(event: "reviewed")
    when PullRequestReviewThread
      pull_request_review_thread_hash(item, options).merge(event: "line-commented")
    when CommitCommentThread
      commit_comment_thread_hash(item, options).merge(event: "commit-commented")
    end
  end

  trace_method :issue_event_hash
  def issue_event_hash(event, options = {})
    repo = repo_path(options, event)
    options = Api::SerializerOptions.from(options)
    actor = event.respond_to?(:event_actor) ? event.event_actor(viewer: options[:current_user]) : event.actor

    hash = {
      id: event.id,
      node_id: global_id_for(event, options),
      url: url("/repos/#{repo}/issues/events/#{event.id}", options),
      actor: user_hash(actor, content_options(options)),
      event: event.event,
      commit_id: commit_id_for(event),
      commit_url: referenced_commit_url(event, options),
      created_at: time(event.created_at),
    }.merge(issue_event_meta_data(event, options))

    if issues = options[:issues]
      hash[:issue] = issues[event.issue_id]
    end

    hash[:performed_via_github_app] = integration_hash(event.performed_via_integration, options)

    hash
  end

  trace_method :issue_event_meta_data
  def issue_event_meta_data(event, options = {})
    case event.event
    when "labeled", "unlabeled"
      {
        label: {
          name: event.label_name,
          color: event.label_color,
        },
      }
    when "closed", "reopened"
      {
        state_reason: event.state_reason
      }
    when "assigned", "unassigned"
      # IssueEvent incorrectly flips subject/actor for (un)assigned events
      assignee = event.actor
      {
        assignee: user_hash(assignee, content_options(options)),
        assigner: user_hash(event.safe_subject, content_options(options)),
      }
    when "milestoned", "demilestoned"
      {
        milestone: {
          title: event.milestone_title,
        },
      }
    when "renamed"
      {
        rename: {
          from: event.title_was,
          to: event.title_is,
        },
      }
    when "review_requested", "review_request_removed"
      hash = {
        review_requester: user_hash(event.actor, content_options(options)),
      }

      if event.safe_subject.is_a?(Team)
        hash[:requested_team] = team_hash(event.safe_subject, options)
      else
        hash[:requested_reviewer] = user_hash(event.safe_subject, content_options(options))
      end

      hash
    when "review_dismissed"
      hash = {
               dismissed_review: {
                 state: ::PullRequestReview.state_name(event.pull_request_review_state_was).to_s,
                 review_id: event.pull_request_review_id,
                 dismissal_message: event.message,
               },
             }

      if event.after_commit_oid
        hash[:dismissed_review][:dismissal_commit_id] = event.after_commit_oid
      end

      hash
    when *IssueEvent::PROJECT_EVENTS
      # Temporary workaround for https://github.com/github/github/issues/84490
      return {} if options[:filter_project_events] && !event.visible_to?(options[:current_user])

      hash = {
        project_card: {
          id: event.card_id,
          url: project_card_url(event.card_id),
          project_id: event.subject_id,
          project_url: project_url(event.subject_id),
          column_name: event.column_name,
        },
      }

      if event.previous_column_name
        hash[:project_card][:previous_column_name] = event.previous_column_name
      end

      hash
    when "locked"
      { lock_reason: event.lock_reason }
    else
      {}
    end
  end

  trace_method :issue_event_detail
  def issue_event_detail(event, options = {})
    return nil unless event&.issue_event_detail
    repo = repo_path(options, event)
    detail = event.issue_event_detail
    options = Api::SerializerOptions.from(options)

    detail = {}.tap do |h|
      if detail.label_name
        h[:label_url] = url("/repos/#{repo}/labels/#{Api::LegacyEncode.encode(detail.label_name)}", options)
        h[:label_name] = detail.label_name
        h[:label_color] = detail.label_color
        h[:label_text_color] = detail.label_text_color
      end

      h[:milestone_url] = url("/repos/#{repo}/milestones/#{detail.milestone_id}", options) if detail.milestone_id

      # return just the subject ID, not the fully hydrated object; this will not always
      # be loaded (bulk export queries, for example, cannot load this polymorphic association)
      h[:subject] = {
        id: detail.subject_id,
        type: detail.subject_type,
      } if detail.subject_id

      h[:title_was] = detail.title_was
      h[:title_is] = detail.title_is

      h[:deployment_id] = detail.deployment_id
      h[:deployment_status_id] = detail.deployment_status_id

      h[:ref] = detail.ref

      h[:before_commit_oid] = detail.before_commit_oid
      h[:after_commit_oid] = detail.after_commit_oid

      h[:message] = detail.message

      if detail.pull_request_review_id
        h[:pull_request_review_url] = url("/repos/#{repo}/pulls/#{event.issue.number}/reviews/#{detail.pull_request_review_id}", options)
        h[:pull_request_review_state_was] = ::PullRequestReview.state_name(detail.pull_request_review_state_was).to_s
      end
      h[:review_request] = detail.review_request_id

      h[:column_name] = detail.column_name
      h[:previous_column_name] = detail.previous_column_name
      h[:card_id] = detail.card_id
      h[:performed_by_project_workflow_action_id] = detail.performed_by_project_workflow_action_id

      h[:lock_reason] = detail.lock_reason
      h[:block_duration_days] = detail.block_duration_days
      h[:state_reason] = detail.state_reason

      # project_url is omitted since ELM doesn't handle these yet
      h[:project_status] = detail.project_status
      h[:project_previous_status] = detail.project_previous_status

      h[:issue_type] = {
        id: detail.issue_type_id,
        name: detail.issue_type_name,
        color: detail.issue_type_color,
      } if detail.issue_type_id
      h[:prev_issue_type] = {
        id: detail.prev_issue_type_id,
        name: detail.prev_issue_type_name,
        color: detail.prev_issue_type_color,
      } if detail.prev_issue_type_id

      h[:trigger_source_url] = detail.trigger_source_url
      h[:trigger_source_type] = detail.trigger_source_type
    end.compact # rubocop:todo Style/MethodCalledOnDoEndBlock
  end

  # Creates a Hash to be serialized to JSON.
  #
  # milestone - Milestone instance.
  # options   - Hash
  #             :repo - Either a Repository or a String of the Repository path:
  #                     "user/repo"
  #
  # Returns a Hash if the Milestone exists, or nil.
  trace_method :milestone_hash
  def milestone_hash(milestone, options = {})
    return nil if !milestone
    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, milestone)
    html_milestone_path = "/#{repo}/milestone/#{milestone.number}"
    api_milestone_path = "/repos/#{repo}/milestones/#{milestone.number}"

    {
      url: url(api_milestone_path, options),
      html_url: html_url(html_milestone_path),
      labels_url: url("#{api_milestone_path}/labels", options),
      id: milestone.id,
      node_id: global_id_for(milestone, options),
      number: milestone.number,
      title: milestone.title,
      description: milestone.description,
      creator: user_hash(milestone.created_by, content_options(options)),
      open_issues: milestone.open_issue_count,
      closed_issues: milestone.closed_issue_count,
      state: milestone.state,
      created_at: time(milestone.created_at),
      updated_at: time(milestone.updated_at),
      due_on: time(milestone.due_on),
      closed_at: time(milestone.closed_at),
    }
  end

  MilestoneFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Milestone {
      id
      number
      title
      description
      state
      createdAt
      updatedAt
      closedAt
      dueOn

      openIssues: issues(states: [OPEN]) {
        totalCount
      }

      closedIssues: issues(states:[CLOSED]) {
        totalCount
      }

      openPullRequests: pullRequests(states: [OPEN]) {
        totalCount
      }

      closedPullRequests: pullRequests(states: [CLOSED, MERGED]) {
        totalCount
      }

      creator {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }

      repository {
        nameWithOwner
      }
    }
  GRAPHQL

  def graphql_milestone_hash(milestone, options = {})
    options   = Api::SerializerOptions.from(options)
    milestone = MilestoneFragment.new(milestone)
    return nil if !milestone

    repo = milestone.repository

    # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
    html_milestone_path = "/#{repo.name_with_owner}/milestone/#{milestone.number}" # rubocop:disable GitHub/DoNotAllowNameWithOwner
    # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
    api_milestone_path = "/repos/#{repo.name_with_owner}/milestones/#{milestone.number}" # rubocop:disable GitHub/DoNotAllowNameWithOwner

    open_count = milestone.open_issues.total_count + milestone.open_pull_requests.total_count
    closed_count = milestone.closed_issues.total_count + milestone.closed_pull_requests.total_count

    {
      url: url(api_milestone_path, options),
      html_url: html_url(html_milestone_path),
      labels_url: url("#{api_milestone_path}/labels", options),
      id: model_id_for_global_id(milestone.id),
      node_id: milestone.id,
      number: milestone.number,
      title: milestone.title,
      description: milestone.description,
      creator: graphql_simple_user_hash(milestone.creator, content_options(options)),
      open_issues: open_count,
      closed_issues: closed_count,
      state: milestone.state.downcase,
      created_at: time(milestone.created_at),
      updated_at: time(milestone.updated_at),
      due_on: time(milestone.due_on),
      closed_at: time(milestone.closed_at),
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # issue_type - IssueType instance.
  #
  # Returns a Hash if the IssueType exists, or nil.
  trace_method :type_hash
  def type_hash(type, options = {})
    return nil unless type

    {
      id: type.id,
      node_id: global_id_for(type, options),
      name: type.name,
      description: type.description,
      color: type.color,
      created_at: time(type.created_at),
      updated_at: time(type.updated_at),
      is_enabled: type.enabled?,
    }
  end

  trace_method :field_hash
  def field_hash(field, options = {})
    return nil unless field
    options = Api::SerializerOptions.from(options)
    result = {
     id: field.id,
     node_id: global_id_for(field, options),
     name: field.name,
     description: field.description,
     data_type: field.data_type,
     created_at: field.created_at,
     updated_at: field.updated_at,
     visibility: visibility_for_api(field.visibility),
   }

    if field.data_type == "single_select" || field.data_type == "multi_select"
      result[:options] = field.options.map do |option|
        {
          id: option.id,
          name: option.name,
          description: option.description,
          color: option.color,
          priority: option.priority,
          created_at: option.created_at,
          updated_at: option.updated_at,
        }
      end
    end

    result
  end

  trace_method :issue_field_value_for_api_hash
  def issue_field_value_for_api_hash(value, options = {})
    return unless value
    options = Api::SerializerOptions.from(options)

    # Build response hash matching the OpenAPI schema
    hash = {
      issue_field_id: value.issue_field.id,
      node_id: global_id_for(value, options),
      data_type: value.issue_field.data_type
    }

    # Handle different data types
    case value.issue_field.data_type
    when "single_select"
      if value.respond_to?(:option) && value.option.present?
        hash[:value] = value.option.id
        hash[:single_select_option] = {
          id: value.option.id,
          name: value.option.name,
          color: value.option.color
        }
      else
        hash[:value] = value.value
        hash[:single_select_option] = nil
      end
    when "multi_select"
      opts = value.respond_to?(:options) ? value.options : []
      if opts.present?
        hash[:value] = opts.map(&:name).join(",")
        hash[:multi_select_options] = opts.map do |opt|
          {
            id: opt.id,
            name: opt.name,
            color: opt.color
          }
        end
      else
        hash[:value] = value.value
        hash[:multi_select_options] = nil
      end
    else
      hash[:value] = value.value
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # label   - Label instance.
  # options - Hash
  #           :repo - Either a Repository or a String of the Repository path:
  #                   "user/repo"
  #
  # Returns a Hash if the Label exists, or nil.
  trace_method :label_hash
  def label_hash(label, options = {})
    return unless label
    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, label)
    hash = {
      id: label.id,
      node_id: global_id_for(label, options),
      url: url("/repos/#{repo}/labels/#{Api::LegacyEncode.encode(label.name)}", options),
      name: label.name,
      color: label.color,
      default: label.default?,
      description: label.description,
    }

    hash
  end

  LabelFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Label {
      id
      name
      color
      description
      isDefault

      repository {
        nameWithOwner
      }
    }
  GRAPHQL

  # Label fragment without repository field — avoids primary read on repository_networks.
  # Callers pass repo path via options[:repo_name_with_display_owner] instead.
  MutationLabelFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Label {
      id
      name
      color
      description
      isDefault
    }
  GRAPHQL

  def graphql_label_hash(label, options = {})
    return unless label

    options        = Api::SerializerOptions.from(options)

    if options[:repo_name_with_display_owner]
      label_fragment = MutationLabelFragment.new(label)
      repo_path = options[:repo_name_with_display_owner]
    else
      label_fragment = LabelFragment.new(label)
      # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
      repo_path = label_fragment.repository.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    return unless label_fragment

    hash = {
      id:      model_id_for_global_id(label_fragment.id),
      node_id: label_fragment.id,
      url:     url("/repos/#{repo_path}/labels/#{Api::LegacyEncode.encode(label_fragment.name.to_s)}", options),
      name:    label_fragment.name,
      color:   label_fragment.color,
      default: label_fragment.is_default,
      description: label_fragment.description,
    }

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # issue   - Issue instance.
  # options - Hash
  #           :repo         - Either a Repository or a String of the Repository
  #                           path: "user/repo"
  #           :repositories - Boolean that determines whether to render the
  #                           Repository data.  Default: false. Only the Issues
  #                           dashboard needs this.  Other calls are scoped
  #                           to a specific Repository.
  #
  # Returns a Hash if the Issue exists, or nil.
  trace_method :issue_hash
  def issue_hash(issue, options = {})
    return nil if !issue

    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, issue)
    issue_path = "/repos/#{repo}/issues/#{issue.number}"

    hash = {
      url: url(issue_path, options),
      repository_url: url("/repos/#{repo}", options),
      labels_url: url("#{issue_path}/labels{/name}", options),
      comments_url: url("#{issue_path}/comments", options),
      events_url: url("#{issue_path}/events", options),
      html_url: issue.url,
      id: issue.id,
      node_id: global_id_for(issue, options),
      number: issue.number,
      title: issue.title,
      user: user_hash(issue.safe_user, content_options(options)),
      labels: issue.labels.map { |l| label_hash(l, options.merge(repo: repo)) },
      state: issue.state,
      locked: issue.locked?,
      assignees: issue.assignees.map { |assignee| simple_user_hash(assignee, content_options(options)) },
      milestone: milestone_hash(issue.milestone, options.merge(repo: repo)),
      comments: issue.issue_comments_count,
      created_at: time(issue.created_at),
      updated_at: time(issue.updated_at),
      closed_at: time(issue.closed_at),
    }

    unless options.changeset_active?(:remove_singular_assignee_from_issues_and_pull_requests)
      hash[:assignee] = user_hash(issue.assignee, content_options(options))
    end

    unless options[:skip_author_association]
      hash[:author_association] = issue.author_association_symbol(options[:current_user]).to_s.upcase
    end

    # Add issue field values if available
    if include_issue_field_values?(issue, options)
      field_values = issue.issue_field_values.to_a
      ::ActiveRecord::Associations::Preloader.new(records: field_values, associations: { issue_field: :owner }).call if field_values.any?
      visible_field_values = Issues.domain.issue_fields.filter_visible_issue_field_values(
        field_values, viewer: options[:current_user]
      )
      hash[:issue_field_values] = visible_field_values.map { |v| issue_field_value_for_api_hash(v, options) }
    end

    if include_issue_type?(issue, options)
      hash[:type] = type_hash(issue.optimized_issue_type, options)
    end

    active_lock_reason = nil
    if issue.active_lock_reason
      active_lock_reason = issue.active_lock_reason.downcase.dasherize
    end

    hash[:active_lock_reason] = active_lock_reason

    if issue.pull_request?
      hash[:draft] = issue.pull_request.draft?
    else
      hash[:sub_issues_summary] = issue.async_sub_issues_summary(calculate: !!options[:calculate_sub_issue_list]).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      # Add parent issue URL if the issue has a parent and the viewer can access the parent's repository
      if issue.is_a?(Issue) && (parent_issue = issue.parent_issue_relation&.source)
        parent_repo = T.must(parent_issue.repository)
        if parent_repo.readable_by?(options[:current_user])
          parent_repo_path = parent_repo.name_with_owner_for_api(use: options[:serialize_login])
          hash[:parent_issue_url] = url("/repos/#{parent_repo_path}/issues/#{parent_issue.number}", options)
        end
      end

      if issue.is_a?(Issue)
        issue_dependencies_summary = issue.async_issue_dependencies_summary(calculate: !!options[:calculate_issue_dependencies_summary]).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        hash[:issue_dependencies_summary] = issue_dependencies_summary.serialize
      end
    end

    # [DEPRECATED] beta header expects an object of nils
    if options.wants_beta_media_type? && !options.changeset_active?(:deprecate_beta_media_type)
      hash.update \
        pull_request: {
          url: nil,
          html_url: nil,
          diff_url: nil,
          patch_url: nil,
          merged_at: nil,
        }
    end

    if options[:repositories] || options.accepts_semantic_version?("extended-search-results")
      hash[:repository] = repository_hash(issue.repository, options)
    end

    if issue.pull_request?
      pr_url = issue.url.sub(/\/issues\/(\d+)$/, '/pull/\1')
      api_pr_url = url("/repos/#{issue.repository.name_with_owner_for_api(use: options[:serialize_login])}/pulls/#{issue.number}")

      hash.update \
        pull_request: {
          url: api_pr_url,
          html_url: pr_url,
          diff_url: "#{pr_url}.diff",
          patch_url: "#{pr_url}.patch",
          merged_at: time(issue.pull_request.merged_at),
        }
    end

    hash.update mime_body_hash(issue, options)

    if options[:full]
      hash[:closed_by] = user_hash(issue.closed_by, content_options(options))
    end

    hash[:reactions] = reactions_rollup(issue, url("#{issue_path}/reactions", options))
    hash[:timeline_url] = url("#{issue_path}/timeline", options)

    hash[:performed_via_github_app] = integration_hash(issue.performed_via_integration, options)

    hash[:state_reason] = issue.state_reason.nil? && issue.closed? && !issue.pull_request? ? "completed" : issue.state_reason

    if !issue.pull_request?
      hash[:pinned_comment] = issue_comment_hash(issue.pinned_issue_comment&.issue_comment, options.merge(issue: issue))
    end

    hash
  end

  trace_method :include_issue_type?
  def include_issue_type?(issue, options)
    return unless issue&.repository&.owner

    issue.repository.owner.issue_types_enabled?
  end

  trace_method :include_issue_field_values?
  def include_issue_field_values?(issue, options)
    return false unless issue&.repository
    IssueFieldsFeature.enabled?(issue.repository, actor: options[:current_user])
  end

  PullRequestIssueFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on PullRequest {
      __typename
      id
      issueDatabaseId
      url
      number
      title
      state
      locked
      createdAt
      updatedAt
      closedAt
      mergedAt
      body
      authorAssociation
      activeLockReason
      isDraft

      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment

      closedBy {
        ... on User {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      repository {
        nameWithOwner
      }

      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }

      milestone {
        ...Api::Serializer::IssuesDependency::MilestoneFragment
      }

      comments {
        count: totalCount
      }

      labels(first: 100) {
        nodes {
          ...Api::Serializer::IssuesDependency::LabelFragment
        }
      }

      assignees(first: 10) {
        nodes {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      viaApp {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragment
      }

      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment
      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment
    }
  GRAPHQL

  # PullRequest issue fragment without repository field — avoids primary read on repository_networks.
  # Callers pass repo path via options[:repo_name_with_display_owner] instead.
  MutationPullRequestIssueFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on PullRequest {
      __typename
      id
      issueDatabaseId
      url
      number
      title
      state
      locked
      createdAt
      updatedAt
      closedAt
      mergedAt
      body
      authorAssociation
      activeLockReason
      isDraft

      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment

      closedBy {
        ... on User {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }

      milestone {
        ...Api::Serializer::IssuesDependency::MilestoneFragment
      }

      comments {
        count: totalCount
      }

      labels(first: 100) {
        nodes {
          ...Api::Serializer::IssuesDependency::MutationLabelFragment
        }
      }

      assignees(first: 10) {
        nodes {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      viaApp {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragment
      }

      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment
    }
  GRAPHQL

  # Issue fragment without repository field — avoids primary read on repository_networks.
  # Callers pass repo path via options[:repo_name_with_display_owner] instead.
  MutationIssueFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Issue {
      __typename
      id
      url
      number
      title
      state
      stateReason
      locked
      createdAt
      updatedAt
      closedAt
      authorAssociation
      activeLockReason

      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment

      subIssuesSummary {
        total,
        completed
        percent_completed: percentCompleted
      }

      issueDependenciesSummary {
        blocked_by: blockedBy
        total_blocked_by: totalBlockedBy
        blocking
        total_blocking: totalBlocking
      }

      closedBy {
        ... on User {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }

      milestone {
        ...Api::Serializer::IssuesDependency::MilestoneFragment
      }

      comments {
        count: totalCount
      }

      labels(first: 100) {
        nodes {
          ...Api::Serializer::IssuesDependency::MutationLabelFragment
        }
      }

      assignees(first: 10) {
        nodes {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      viaApp {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragment
      }

      pinnedIssueComment {
        issueComment {
          ...Api::Serializer::IssuesDependency::IssueCommentFragment
        }
      }

      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment
    }
  GRAPHQL

  IssueFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Issue {
      __typename
      id
      url
      number
      title
      state
      stateReason
      locked
      createdAt
      updatedAt
      closedAt
      authorAssociation
      activeLockReason

      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment

      subIssuesSummary {
        total,
        completed
        percent_completed: percentCompleted
      }

      issueDependenciesSummary {
        blocked_by: blockedBy
        total_blocked_by: totalBlockedBy
        blocking
        total_blocking: totalBlocking
      }

      closedBy {
        ... on User {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      repository {
        nameWithOwner
      }

      author {
        ...Api::Serializer::UserDependency::SimpleUserFragment
      }

      milestone {
        ...Api::Serializer::IssuesDependency::MilestoneFragment
      }

      comments {
        count: totalCount
      }

      labels(first: 100) {
        nodes {
          ...Api::Serializer::IssuesDependency::LabelFragment
        }
      }

      assignees(first: 10) {
        nodes {
          ...Api::Serializer::UserDependency::SimpleUserFragment
        }
      }

      viaApp {
        ...Api::Serializer::IntegrationsDependency::IntegrationFragment
      }

      pinnedIssueComment {
        issueComment {
          ...Api::Serializer::IssuesDependency::IssueCommentFragment
        }
      }

      ...Api::Serializer::ReactionsDependency::ReactionsRollupFragment
      ...Api::Serializer::GraphqlHelperDependency::MimeBodyFragment
    }
  GRAPHQL

  def graphql_issue_hash(issue, options)
    options = Api::SerializerOptions.from(options)

    if options[:repo_name_with_display_owner]
      issue = if issue.is_a? Api::App::PlatformTypes::PullRequest
        MutationPullRequestIssueFragment.new(issue)
      else
        MutationIssueFragment.new(issue)
      end
      repo_nwo = options[:repo_name_with_display_owner]
    else
      issue = if issue.is_a? Api::App::PlatformTypes::PullRequest
        PullRequestIssueFragment.new(issue)
      else
        IssueFragment.new(issue)
      end
      repo_nwo = nil
    end

    return nil if !issue
    # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
    repo_nwo ||= issue.repository.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner
    repo_path = "/repos/#{repo_nwo}"
    issue_path = "#{repo_path}/issues/#{issue.number}"

    issue_url     = url(issue_path, options)
    repo_url      = url(repo_path, options)
    labels_url    = url("#{issue_path}/labels{/name}", options)
    comments_url  = url("#{issue_path}/comments", options)
    events_url    = url("#{issue_path}/events", options)
    reactions_url = url("#{issue_path}/reactions", options)
    timeline_url  = url("#{issue_path}/timeline", options)

    id = if issue.is_a? Api::App::PlatformTypes::PullRequest
      issue.issue_database_id
    else
      model_id_for_global_id(issue.id)
    end

    state = if issue.is_a?(Api::App::PlatformTypes::PullRequest)
      issue.state == "MERGED" ? "CLOSED" : issue.state
    else
      issue.state
    end

    state_reason = if issue.is_a?(Api::App::PlatformTypes::PullRequest)
      nil
    else
      issue.state_reason
    end

    hash = {
      url: issue_url,
      repository_url: repo_url,
      labels_url: labels_url,
      comments_url: comments_url,
      events_url: events_url,
      html_url: issue.url.to_s,
      id: id,
      node_id: issue.id,
      number: issue.number,
      title: issue.title,
      user: graphql_simple_user_hash(issue.author, options),
      labels: issue.labels.nodes.map { |label| graphql_label_hash(label, options) },
      state: state.downcase,
      locked: issue.locked,
      assignee: graphql_simple_user_hash(issue.assignees.nodes.first, options),
      assignees: issue.assignees.nodes.map { |user| graphql_simple_user_hash(user, options) },
      milestone: graphql_milestone_hash(issue.milestone, options),
      comments: issue.comments.count,
      created_at: time(issue.created_at),
      updated_at: time(issue.updated_at),
      closed_at: time(issue.closed_at),
      author_association: issue.author_association,
    }

    active_lock_reason = nil
    if issue.active_lock_reason
      active_lock_reason = issue.active_lock_reason.downcase.dasherize
    end

    hash[:active_lock_reason] = active_lock_reason

    # [DEPRECATED] beta header expects an object of nils
    if options.wants_beta_media_type? && !options.changeset_active?(:deprecate_beta_media_type)
      hash.update \
        pull_request: {
          url: nil,
          html_url: nil,
          diff_url: nil,
          patch_url: nil,
          merged_at: nil,
        }
    end

    if !options[:repo_name_with_display_owner] && (options[:repositories] || options.accepts_semantic_version?("extended-search-results"))
      hash[:repository] = graphql_repository_hash(issue.repository)
    end

    if issue.is_a? Api::App::PlatformTypes::PullRequest
      pr_url = issue.url.to_s
      api_pr_url = url("/repos/#{repo_nwo}/pulls/#{issue.number}")

      hash[:draft] = issue.is_draft
      hash.update \
        pull_request: {
          url: api_pr_url,
          html_url: pr_url,
          diff_url: "#{pr_url}.diff",
          patch_url: "#{pr_url}.patch",
          merged_at: time(issue.merged_at)
        }
    else
      hash[:sub_issues_summary] = issue.sub_issues_summary

      if issue.issue_dependencies_summary.present?
        hash[:issue_dependencies_summary] = issue.issue_dependencies_summary
      end
    end

    hash.update(graphql_mime_body_hash(issue, options))

    # GraphQL will return an empty string for nil bodies, but the existing REST API
    # returns nil.
    if hash.key?(:body)
      hash[:body] = hash[:body].presence
    end

    if options[:full]
      hash[:closed_by] = graphql_simple_user_hash(issue.closed_by, content_options(options))
    end

    hash[:reactions] = graphql_reactions_rollup(issue, reactions_url)
    hash[:timeline_url] = timeline_url
    hash[:performed_via_github_app] = graphql_integration_hash(issue.via_app)

    hash[:state_reason] = state_reason&.downcase

    unless issue.is_a? Api::App::PlatformTypes::PullRequest
      if issue.respond_to?(:pinned_issue_comment)
        hash[:pinned_comment] = issue.pinned_issue_comment ? graphql_issue_comment_hash(issue.pinned_issue_comment.issue_comment, options) : nil
      end
    end

    hash
  end

  private

  def visibility_for_api(visibility)
    return PUBLIC_VISIBILITY_ORGANIZATION_MEMBERS_ONLY if visibility == INTERNAL_VISIBILITY_ORG_ONLY

    visibility
  end

  def commit_id_for(event)
    return nil unless link_to_referenced_commit?(event)
    # an oid isn't being persisted to the commit_id column specifically for head_ref_force_pushed issue events, and
    # attempting to do so causes pull request synchronization to fail due to the unique database index on the issue
    # events table for issue id, event name, and commit id. The after_commit_id is always being persisted for these
    # events as an event detail, and can be surfaced to end users as the canonical oid for the associated event
    return event.after_commit_oid if event.event == "head_ref_force_pushed"

    event.commit_id
  end

  def link_to_referenced_commit?(event)
    event.repository_for_commit.public? ||
      event.repository_for_commit == event.repository
  end

  def referenced_commit_url(event, options)
    if commit_id_for(event)
      url("/repos/#{event.repository_for_commit.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{commit_id_for(event)}")
    end
  end
end
