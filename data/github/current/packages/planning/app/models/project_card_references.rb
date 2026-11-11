# typed: false
# frozen_string_literal: true

# Resolve any references to issues, projects, and team discussions found in the
# text of a note card.
#
# Only returns references to resources that the viewer has access to.
class ProjectCardReferences
  include GitHub::IssueReferenceResolution
  def initialize(project:, text:, viewer:)
    @text = text.to_s
    @parent_project = project
    @viewer = viewer
    scan_for_references
  end

  # Accepts a list of organization IDs that should be excluded from rendered
  # references, then removes results in those orgs from all references.
  #
  # unauthorized_orgs - Array of Integer representing org IDs.
  #
  # Returns nothing.
  def filter_unauthorized_orgs(unauthorized_orgs)
    return if unauthorized_orgs.empty?
    issues.reject! { |issue| unauthorized_orgs.include? issue.owner.id }
    discussions.reject! { |discussion| unauthorized_orgs.include? discussion.team.organization.id }
    projects.reject! do |project|
      case project.owner
      when Repository
        unauthorized_orgs.include? project.owner.owner.id
      when Organization
        unauthorized_orgs.include? project.owner.id
      end
    end

    # reset cached reference counts
    @accessible_reference_count = nil
  end

  # Count of raw references parsed from the text for all resources that may
  # or may not exist and be visible to the viewer.
  def raw_reference_count
    @raw_reference_count ||= @references.values.flatten(1).size
  end

  # Count of references to resources that exist and are visible to the viewer.
  def accessible_reference_count
    @accessible_reference_count ||= issues.size + discussions.size + projects.size
  end

  # Does the text only reference a single resource and nothing else?
  # WARNING This can return `true` when there are no accessible references
  def single_reference?
    !non_reference_text? && raw_reference_count == 1
  end

  # Does the text reference a single issue and nothing else?
  def single_issue_reference?
    single_reference? && issues.length == 1
  end

  # Get the single issue referenced by the text.
  def issue
    issues.first if single_issue_reference?
  end

  # Does the text reference a single project and nothing else?
  def single_project_reference?
    single_reference? && projects.length == 1
  end

  # Get the single project referenced by the text.
  def project
    projects.first if single_project_reference?
  end

  # Does the text reference a single discussion and nothing else?
  def single_discussion_reference?
    single_reference? && discussions.length == 1
  end

  # Get the single discussion referenced by the text.
  def discussion
    discussions.first if single_discussion_reference?
  end

  # Get the content params to use to create an issue-backed card from the
  # single issue referenced by the text.
  def content_params
    content = issue
    { content_id: content.id, content_type: content.class.name }
  end

  # Can the single issue referenced by the text be added to the project as an
  # issue-backed card?
  def can_add_content?
    content = issue
    content && @parent_project.user_can_add_content?(user: @viewer, content: content)
  end

  # Returns the card in the project already associated with the single issue
  # referenced by the text.
  def card
    return @card if defined? @card
    @card = @parent_project.cards.for_content(issue).first
  end

  # Does the text contain anything but references?
  # WARNING This can return `false` when there are no accessible references
  def non_reference_text?
    @non_reference_text.present? || @duplicate_references
  end

  # Get all the issues referenced by the text readable by the viewer.
  def issues
    @issues ||= begin
      issues = []
      @references[:issues].each do |repository, reference|
        issue = resolve_issue_reference_with_permissions(reference, repository, @viewer)
        issues << issue if issue
      end

      issues
    end
  end

  # Get all the discussions referenced by the text readable by the viewer.
  def discussions
    @discussions ||= begin
      discussions = []
      @references[:discussions].each do |org_login, team_name, discussion_number|
        team = Team.with_org_name_and_slug(org_login, team_name)
        next unless team

        discussion = team.discussion_posts.find_by_number(discussion_number)
        if discussion&.readable_by?(@viewer)
          discussions << discussion
        end
      end
      discussions
    end
  end

  # Get all the projects referenced by the text readable by the viewer.
  def projects
    @projects ||= begin
      projects = []
      @references[:projects].each do |reference|
        owner = if reference[:repo]
          find_repo(reference[:repo], nil)
        elsif reference[:org]
          Organization.find_by(login: reference[:org])
        elsif reference[:user]
          User.find_by(login: reference[:user])
        end

        if owner
          project = owner.visible_projects_for(@viewer).find_by(number: reference[:number])
          if project != @parent_project && project&.readable_by?(@viewer)
            projects << project
          end
        end
      end

      projects
    end
  end

  def channels
    channels = []
    issues.each do |issue|
      channels << GitHub::WebSocket::Channels.issue(issue)
      if issue.pull_request?
        channels.concat(GitHub::WebSocket::Channels.pull_request_mergeable(issue.pull_request))
        channels << GitHub::WebSocket::Channels.pull_request(issue.pull_request)
      end
    end
    projects.each do |project|
      channels << GitHub::WebSocket::Channels.project(project)
    end
    channels
  end

  private

  NUMBER = GitHub::HTML::IssueMentionFilter::NUMBER
  NWO = GitHub::HTML::IssueMentionFilter::NWO
  QUERY_AND_HASH = %r<(?:[?#][^\s]*(?=\s|$))?>

  def reference_patterns
    github_url = Regexp.escape(GitHub.url)
    full_url_org_project_mention = %r<#{GITHUB_URL}/orgs/([\w-]+)/projects/#{NUMBER}#{QUERY_AND_HASH}>
    full_url_user_project_mention = %r<#{GITHUB_URL}/users/([\w-]+)/projects/#{NUMBER}#{QUERY_AND_HASH}>
    full_url_repo_project_mention = %r<#{GITHUB_URL}/#{NWO}/projects/#{NUMBER}#{QUERY_AND_HASH}>
    full_url_discussion_mention = %r<#{GITHUB_URL}/orgs/([\w-]+)/teams/([\w-]+)/discussions/#{NUMBER}#{QUERY_AND_HASH}>

    Regexp.union(
      GitHub::HTML::IssueMentionFilter::REPO_ISSUE_REFERENCE,
      GitHub::HTML::IssueMentionFilter::KEYWORD_ISSUE_REFERENCE,
      GitHub::HTML::IssueMentionFilter.full_url_issue_mention,
      full_url_org_project_mention,
      full_url_user_project_mention,
      full_url_repo_project_mention,
      full_url_discussion_mention,
    )
  end

  def scan_for_references
    references = { issues: [], projects: [], discussions: [] }
    repository = @parent_project.owner if @parent_project.owner.is_a?(Repository)

    remaining_text = @text.gsub(reference_patterns) do
      match = Regexp.last_match

      full_reference = match[0].strip
      # REPO_ISSUE_REFERENCE pattern match
      repo_prefix, repo_issue_number = match[1], match[3]
      if repo_issue_number
        references[:issues] << [repository, full_reference]
        # Remove nwo and issue number but retain prefix text
        next repo_prefix
      end

      # KEYWORD_ISSUE_REFERENCE pattern match
      keyword_prefix, keyword_issue_number = match[4], match[6]
      if keyword_issue_number
        references[:issues] << [repository, full_reference]
        # Remove issue number but retain prefix text
        next keyword_prefix
      end

      # FULL_URL_ISSUE_MENTION pattern match
      url_nwo, url_issue_number = match[7], match[8]
      if url_issue_number
        references[:issues] << [url_nwo, full_reference]
        # Remove URL
        next ""
      end

      # FULL_URL_ORG_PROJECT_MENTION pattern match
      org_project_owner, org_project_number  = match[10], match[11]
      if org_project_number
        references[:projects] << { org: org_project_owner, number: org_project_number }
        # Remove URL
        next ""
      end

      # FULL_URL_USER_PROJECT_MENTION pattern match
      user_project_owner, user_project_number  = match[12], match[13]
      if user_project_number
        references[:projects] << { user: user_project_owner, number: user_project_number }
        # Remove URL
        next ""
      end

      # FULL_URL_REPO_PROJECT_MENTION pattern match
      repo_project_nwo, repo_project_number  = match[14], match[15]
      if repo_project_number
        references[:projects] << { repo: repo_project_nwo, number: repo_project_number }
        # Remove URL
        next ""
      end

      # FULL_URL_DISCUSSION_MENTION pattern match
      discussion_org, discussion_team, discussion_number = match[16], match[17], match[18]
      if discussion_number
        references[:discussions] << [discussion_org, discussion_team, discussion_number]
        # Remove URL
        next ""
      end
    end

    @duplicate_references = references.values.any? do |refs|
      refs.uniq!.present?
    end

    @non_reference_text = remaining_text
    @references = references
  end
end
