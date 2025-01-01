# typed: true
# frozen_string_literal: true

module Api::Serializer::IssuesDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer::UserDependency }
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  class UnsupportedCrossReferenceSource < RuntimeError
    def initialize(source)
      super "Unsupported CrossReference source: #{source.class.name}"
    end
  end

  def issue_comment_hash(comment, options = {})
    return nil if !comment
    options = Api::SerializerOptions.from(options)

    repo = repo_path(options, comment)

    hash = {
      url: url("/repos/#{repo}/issues/comments/#{comment.id}", options),
      html_url: comment.permalink,
      issue_url: url("/repos/#{repo}/issues/#{comment.issue.try(:number)}", options),
      id: comment.id,
      node_id: global_id_for(comment, options),
      user: T.unsafe(self).user_hash(comment.safe_user, content_options(options)),
      created_at: time(comment.created_at),
      updated_at: time(comment.updated_at),
      author_association: comment.author_association(options[:current_user]).to_s,
    }.update(mime_body_hash(comment, options))

    hash[:reactions] = T.unsafe(self).reactions_rollup(comment, url("/repos/#{repo}/issues/comments/#{comment.id}/reactions", options))
    hash[:performed_via_github_app] = T.unsafe(self).integration_hash(comment.performed_via_integration, options)

    hash
  end

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

  def search_label_hash(label_result, options = {})
    label = label_result["_model"]
    return unless label

    label_hash(label, options)
  end

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
      commit_id: link_to_referenced_commit?(event) ? event.commit_id : nil,
      commit_url: referenced_commit_url(event, options),
      created_at: time(event.created_at),
    }.merge(issue_event_meta_data(event, options))

    if issues = options[:issues]
      hash[:issue] = issues[event.issue_id]
    end

    hash[:performed_via_github_app] = integration_hash(event.performed_via_integration, options)

    hash
  end

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

  # Creates a Hash to be serialized to JSON.
  #
  # milestone - Milestone instance.
  # options   - Hash
  #             :repo - Either a Repository or a String of the Repository path:
  #                     "user/repo"
  #
  # Returns a Hash if the Milestone exists, or nil.
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
      due_on: time(milestone.due_date),
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
  def type_hash(type, options = {})
    return nil unless type

    {
      id: type.id,
      node_id: global_id_for(type, options),
      name: type.name,
      description: type.description,
      created_at: time(type.created_at),
      updated_at: time(type.updated_at),
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # label   - Label instance.
  # options - Hash
  #           :repo - Either a Repository or a String of the Repository path:
  #                   "user/repo"
  #
  # Returns a Hash if the Label exists, or nil.
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

  def graphql_label_hash(label, options = {})
    return unless label

    options        = Api::SerializerOptions.from(options)
    label_fragment = LabelFragment.new(label)
    # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
    repo_path      = label_fragment.repository.name_with_owner # rubocop:disable GitHub/DoNotAllowNameWithOwner

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
      assignee: user_hash(issue.assignee, content_options(options)),
      assignees: issue.assignees.map { |assignee| simple_user_hash(assignee, content_options(options)) },
      milestone: milestone_hash(issue.milestone, options.merge(repo: repo)),
      comments: issue.issue_comments_count,
      created_at: time(issue.created_at),
      updated_at: time(issue.updated_at),
      closed_at: time(issue.closed_at),
      author_association: issue.author_association_symbol(options[:current_user]).to_s.upcase,
    }

    if options[:include_issue_type]
      hash[:type] = type_hash(issue.issue_type, options)
    end

    active_lock_reason = nil
    if issue.active_lock_reason
      active_lock_reason = issue.active_lock_reason.downcase.dasherize
    end

    hash[:active_lock_reason] = active_lock_reason

    if issue.pull_request?
      hash[:draft] = issue.pull_request.draft?
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

    hash
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

  def graphql_issue_hash(issue, options)
    options = Api::SerializerOptions.from(options)

    issue = if issue.is_a? Api::App::PlatformTypes::PullRequest
      PullRequestIssueFragment.new(issue)
    else
      IssueFragment.new(issue)
    end

    return nil if !issue
    # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
    repo_path = "/repos/#{issue.repository.name_with_owner}" # rubocop:disable GitHub/DoNotAllowNameWithOwner
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

    if options[:repositories] || options.accepts_semantic_version?("extended-search-results")
      hash[:repository] = graphql_repository_hash(issue.repository)
    end

    if issue.is_a? Api::App::PlatformTypes::PullRequest
      pr_url = issue.url.to_s
      # Hash is used specifically for GraphQL and name_with_owner in GraphQL already return display name_with_owner
      api_pr_url = url("/repos/#{issue.repository.name_with_owner}/pulls/#{issue.number}") # rubocop:disable GitHub/DoNotAllowNameWithOwner

      hash[:draft] = issue.is_draft
      hash.update \
        pull_request: {
          url: api_pr_url,
          html_url: pr_url,
          diff_url: "#{pr_url}.diff",
          patch_url: "#{pr_url}.patch",
          merged_at: time(issue.merged_at)
        }
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

    hash
  end

  private

  def link_to_referenced_commit?(event)
    event.repository_for_commit.public? ||
      event.repository_for_commit == event.repository
  end

  def referenced_commit_url(event, options)
    if event.commit_id && link_to_referenced_commit?(event)
      url("/repos/#{event.repository_for_commit.name_with_owner_for_api(use: options[:serialize_login])}/commits/#{event.commit_id}")
    end
  end
end
