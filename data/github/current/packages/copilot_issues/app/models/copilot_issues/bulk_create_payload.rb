# typed: true
# frozen_string_literal: true

module CopilotIssues
  class BulkCreatePayload
    include CopilotIssues::Metrics

    class AgentAssignmentAttributes < T::Struct
      const :target_repo, T.nilable(String)
      const :base_ref, T.nilable(String)
      const :custom_instructions, T.nilable(String)
      const :custom_agent, T.nilable(String)
      const :model, T.nilable(String)
    end

    # *IssueMetadata represents the payload from the client to create issues in bulk.
    IssueMetadata = T.type_alias { T.any(DraftIssueMetadata, ExistingIssueMetadata) }

    class Project < T::Struct
      const :id, T.nilable(String)
      const :title, T.nilable(String)
    end

    class IssueFieldInput < T::Struct
      const :field_id, String
      const :text_value, T.nilable(String)
      const :single_select_option_id, T.nilable(String)
      const :date_value, T.nilable(String)
      const :number_value, T.nilable(Float)
    end

    class DraftIssueMetadata < T::Struct
      const :title, String
      const :tag, String
      const :repository_id, Integer
      const :body, T.nilable(String)
      const :parent_tag, T.nilable(String)
      const :labels, T::Array[String]
      const :assignees, T::Array[String]
      const :milestone, T.nilable(String)
      const :issue_type, T.nilable(String)
      const :template, T.nilable(String)
      # Projects can be either strings (legacy: titles only) or hashes (new: with id and title)
      const :projects, T::Array[T.any(String, Project)]
      const :blocked_by_tags, T::Array[String]
      const :agent_assignment, T.nilable(AgentAssignmentAttributes)
      const :issue_fields, T::Array[IssueFieldInput]
    end

    class ExistingIssueMetadata < T::Struct
      const :tag, String
      const :parent_tag, T.nilable(String)
      const :repository_id, Integer
      const :number, Integer
      const :blocked_by_tags, T::Array[String]
      const :agent_assignment, T.nilable(AgentAssignmentAttributes)
    end

    # *IssueAttributes is the internal representation, with resolved metadata values.
    IssueAttributes = T.type_alias { T.any(DraftIssueAttributes, ExistingIssueAttributes) }

    class DraftIssueAttributes < T::Struct
      const :tag, String
      const :title, String
      const :repository, Repository
      const :body, T.nilable(String)
      const :labels, T::Array[Label]
      const :assignees, T::Array[User]
      const :milestone, T.nilable(Milestone)
      const :issue_type, T.nilable(IssueType)
      const :template_name, T.nilable(String)
      # Legacy field for backward compatibility. When present, takes priority over :projects.
      const :project_titles, T::Array[String]
      # Store projects with both id and title when available
      const :projects, T::Array[Project]
      const :blocked_by_tags, T::Array[String]
      const :agent_assignment, T.nilable(AgentAssignmentAttributes)
      const :issue_fields, T.nilable(T::Array[IssueField::IssueFieldAttributesType])
      prop :parent_issue_id, T.nilable(String), default: nil
    end

    class ExistingIssueAttributes < T::Struct
      const :tag, String
      const :repository, Repository
      const :number, Integer
      const :blocked_by_tags, T::Array[String]
      const :agent_assignment, T.nilable(AgentAssignmentAttributes)
      prop :parent_issue_id, T.nilable(String), default: nil
    end

    class IssueNode < T::Struct
      prop :tag, String
      prop :item, IssueAttributes
      prop :parent, T.nilable(IssueNode)
      prop :children, T::Array[IssueNode]
    end

    class CreatedIssue < T::Struct
      const :global_relay_id, String
      const :database_id, Integer
      const :number, Integer
      const :url, String
      const :title, String
      const :repository_id, Integer
      const :errors, T.nilable(T::Array[Errors::ContinuableError])
      const :dependency_errors, T.nilable(T::Array[Errors::DependencyAssignmentError])
    end

    sig { returns(T::Array[IssueMetadata]) }
    attr_reader :issues

    sig { returns(T::Hash[String, IssueNode]) }
    attr_reader :draft_issue_tree_map

    sig { returns(T::Hash[Integer, Repository]) }
    attr_reader :repositories

    sig { returns(User) }
    attr_reader :current_user

    sig { returns(T::Hash[String, T::Array[Errors::ContinuableError]]) }
    attr_reader :errors

    sig { returns(T::Hash[String, T::Array[Errors::DependencyAssignmentError]]) }
    attr_reader :dependency_errors

    sig { params(issues_payload: T::Array[T::Hash[String, T.untyped]], current_user: User).void }
    def initialize(issues_payload, current_user)
      @current_user = T.let(current_user, User)
      @issues = T.let([], T::Array[IssueMetadata])
      @errors = T.let({}, T::Hash[String, T::Array[Errors::ContinuableError]])
      @dependency_errors = T.let({}, T::Hash[String, T::Array[Errors::DependencyAssignmentError]])

      issues_payload.each do |metadata|
        metadata = metadata.with_indifferent_access

        agent_assignment = parse_agent_assignment(metadata[:agent_assignment])

        if metadata[:number].present?
          @issues << ExistingIssueMetadata.new(
            tag: metadata[:tag],
            parent_tag: metadata[:parent_tag],
            repository_id: metadata[:repository_id].to_i,
            number: metadata[:number].to_i,
            blocked_by_tags: metadata[:blocked_by_tags] || [],
            agent_assignment: agent_assignment,
          )
        else
          # Normalize projects to match the expected type
          normalized_projects = T.let([], T::Array[T.any(String, Project)])
          if metadata[:projects].is_a?(Array)
            metadata[:projects].each do |project|
              case project
              when String
                normalized_projects << project
              when Hash
                # Convert to symbol-keyed hash with nilable string values
                project_hash = project.symbolize_keys.slice(:id, :title)
                normalized_projects << Project.new(
                  id: project_hash[:id].to_s.presence,
                  title: project_hash[:title].to_s.presence
                )
              end
            end
          end

          normalized_issue_fields = parse_issue_fields(metadata[:issue_fields])

          @issues << DraftIssueMetadata.new(
            title: metadata[:title],
            body: metadata[:body],
            tag: metadata[:tag],
            parent_tag: metadata[:parent_tag],
            repository_id: metadata[:repository_id].to_i,
            labels: metadata[:labels] || [],
            assignees: metadata[:assignees] || [],
            milestone: metadata[:milestone],
            issue_type: metadata[:issue_type],
            template: metadata[:template],
            projects: normalized_projects,
            blocked_by_tags: metadata[:blocked_by_tags] || [],
            agent_assignment: agent_assignment,
            issue_fields: normalized_issue_fields,
          )
        end

        # Initialize errors for each issue tag
        @errors[metadata[:tag]] = T.let([], T::Array[Errors::ProjectAssignmentError])
        @dependency_errors[metadata[:tag]] = T.let([], T::Array[Errors::DependencyAssignmentError])
      end
      @repositories = T.let(unique_repositories, T::Hash[Integer, Repository])
      @draft_issue_tree_map = T.let(build_draft_issue_tree_map, T::Hash[String, IssueNode])
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def serialize
      issues.map(&:serialize)
    end

    sig { params(issue_attributes: IssueAttributes, repository: Repository).returns(CreatedIssue) }
    def process_issue(issue_attributes, repository)
      case issue_attributes
      when DraftIssueAttributes
        create_issue(issue_attributes, repository)
      when ExistingIssueAttributes
        fetch_and_reparent_existing_issue(issue_attributes, repository)
      else
        T.absurd(issue_attributes)
      end
    end

    sig { params(issue_tag: String, blocked_by_tags: T::Array[String], created_issues_map: T::Hash[String, CreatedIssue], repository: Repository).void }
    def assign_issue_dependencies(issue_tag, blocked_by_tags, created_issues_map, repository)
      collect_metrics("copilot_issues.bulk_create.assign_issue_dependencies") do
        return if blocked_by_tags.empty?

        issue_data = created_issues_map[issue_tag]
        unless issue_data
          T.must(@dependency_errors[issue_tag]) << Errors::DependencyAssignmentError.new(issue_tag, ["Issue not found"])
          return
        end

        # Load the issue from the database
        issue = Issues.domain.by_number(issue_data.number, repo_id: issue_data.repository_id).ok
        issue = T.cast(issue, T.nilable(Issue))
        unless issue
          T.must(@dependency_errors[issue_tag]) << Errors::DependencyAssignmentError.new(issue_tag, ["Issue not found in database"])
          return
        end

        blocked_by_tags.each do |blocking_issue_tag|
          blocking_issue_data = created_issues_map[blocking_issue_tag]
          unless blocking_issue_data
            T.must(@dependency_errors[issue_tag]) << Errors::DependencyAssignmentError.new(blocking_issue_tag, ["Blocking issue not found"])
            next
          end

          # Load the blocking issue from the database
          blocking_issue = Issues.domain.by_number(blocking_issue_data.number, repo_id: blocking_issue_data.repository_id).ok
          blocking_issue = T.cast(blocking_issue, T.nilable(Issue))
          unless blocking_issue
            T.must(@dependency_errors[issue_tag]) << Errors::DependencyAssignmentError.new(blocking_issue_tag, ["Blocking issue not found in database"])
            next
          end

          begin
            issue.throttle_writes do
              issue.add_blocked_by!(blocking_issue, current_user)
            end
          rescue => e
            T.must(@dependency_errors[issue_tag]) << Errors::DependencyAssignmentError.new(blocking_issue_tag, [e.message])
          end
        end
      end
    end

    sig do
      params(
        issue: Issue,
        issue_tag: String,
        agent_assignment: AgentAssignmentAttributes,
        repository: Repository
      ).void
    end
    def assign_copilot_to_created_issue(issue, issue_tag, agent_assignment, repository)
      collect_metrics("copilot_issues.bulk_create.assign_copilot_to_created_issue") do
        # Resolve target repository
        target_repository = if agent_assignment.target_repo.present?
          begin
            Repository.nwo(agent_assignment.target_repo)
          rescue => e
            T.must(@errors[issue_tag]) << Errors::AgentAssignmentError.new(issue.url, T.must(agent_assignment.target_repo), [e.message])
            return
          end
        else
          repository
        end

        unless target_repository
          T.must(@errors[issue_tag]) << Errors::AgentAssignmentError.new(issue.url, T.must(agent_assignment.target_repo), ["Target repository not found"])
          return
        end

        # Build assignment attributes
        assignment_attributes = Issues::AgentAssignmentNewAttributes.new(
          target_repository: target_repository,
          base_ref: agent_assignment.base_ref || target_repository.default_branch,
          custom_instructions: agent_assignment.custom_instructions,
          custom_agent: agent_assignment.custom_agent,
          model: agent_assignment.model,
          remote_ip: nil
        )

        # Get copilot token
        token = CopilotSessions::CopilotApiToken.get_encrypted(
          user: current_user,
          entry_point: :bulk_create_agent_assignment,
          user_session: nil
        )

        begin
          # Call the domain method to assign copilot
          Issues.domain.copilot.assign_copilot_to_issues(
            actor: current_user,
            issues: [issue],
            assignment_attributes: assignment_attributes,
            token: token,
            use_async: false
          )
        rescue => e
          T.must(@errors[issue_tag]) << Errors::AgentAssignmentError.new(issue.url, target_repository.name_with_display_owner, [e.message])
        end
      end
    end

    private

    sig { params(issue_attributes: DraftIssueAttributes, repository: Repository).returns(CreatedIssue) }
    def create_issue(issue_attributes, repository)
      collect_metrics("copilot_issues.bulk_create.create_issue_with_issues_domain") do
        parent_issue = if issue_attributes.parent_issue_id
          parsed = Platform::Helpers::GlobalId.parse(issue_attributes.parent_issue_id)
          case parsed
          when Platform::Helpers::GlobalId::Next
            Platform::Objects::Issue.load_from_next_global_id(parsed)
          else
            Platform::Objects::Issue.load_from_global_id(parsed.id)
          end.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        end

        create_issue_attributes = ::Issues::CreateIssueAttributes.new(
          title: issue_attributes.title,
          body: issue_attributes.body,
          repository: repository,
          labels: issue_attributes.labels,
          assignees: issue_attributes.assignees,
          milestone: issue_attributes.milestone,
          issue_type: issue_attributes.issue_type,
          template_name: issue_attributes.template_name,
          parent_issue: parent_issue,
          issue_fields: issue_attributes.issue_fields
        )

        # User needs at least read access to create an issue.
        # For sub-issues permission, we don't need to check it here because the domain layer will validate it.
        if !repository.readable_by?(current_user)
          raise Errors::ValidationOrAccessError.new(
            "Read access is required to create issues in this repository.",
            repository_id: repository.id,
            issue_tag: issue_attributes.tag,
          )
        end

        result = Issues.domain.create(create_issue_attributes, current_user, viewer: current_user)

        if (issue = result.ok)
          issue = T.cast(issue, ::Issue)
          global_relay_id = issue.global_relay_id

          # Add the issue to projects if any are specified
          # Support both new format (projects with IDs) and legacy format (project_titles)
          # Always prefer project_titles if present for maximum backward compatibility
          projects_to_assign = if issue_attributes.project_titles.any?
            # Convert legacy project_titles to new format
            issue_attributes.project_titles.map { |title| Project.new(title: title, id: nil) }
          elsif issue_attributes.projects.any?
            issue_attributes.projects
          else
            []
          end

          if projects_to_assign.any?
            assign_issue_to_projects(global_relay_id, issue_attributes.tag, projects_to_assign, repository)
          end

          if issue_attributes.agent_assignment.present? && FeatureFlag.vexi.enabled?(:copilot_api_bulk_create_agent_assignments, current_user, default: false)
            assign_copilot_to_created_issue(issue, issue_attributes.tag, T.must(issue_attributes.agent_assignment), repository)
          end

          CreatedIssue.new(
            global_relay_id: global_relay_id,
            database_id: T.must(issue.id),
            title: issue.title,
            number: issue.number.to_i,
            url: issue.permalink,
            repository_id: repository.id,
            errors: errors[issue_attributes.tag],
            dependency_errors: dependency_errors[issue_attributes.tag],
          )
        else
          error = T.must(result.error)
          raise Errors::ErrorParser.parse_domain_error(error, "Issue creation failed.", repository.id, issue_tag: issue_attributes.tag)
        end
      end
    end

    sig { params(issue_attributes: ExistingIssueAttributes, repository: Repository).returns(CreatedIssue) }
    def fetch_and_reparent_existing_issue(issue_attributes, repository)
      collect_metrics("copilot_issues.bulk_create.fetch_existing_issue") do
        issue = Issues.domain.by_number(issue_attributes.number, repo_id: repository.id).ok
        raise Errors::ServiceError.new("Issue not found") if issue.nil?
        issue = T.cast(issue, Issue)

        # If we have a parent issue, see if we need to reparent
        if issue_attributes.parent_issue_id.present?
          # Find existing parent issue
          # issues/sub_issues tables are in different schema domains; joining is a violation
          parent_relation = issue.parent_issue_relation
          parent_issue = parent_relation&.source
          existing_parent_id = parent_issue&.global_relay_id

          # If the new parent is different, we need to update _this_ issue to point to its new parent.
          # We do this via GraphQL to leverage existing validation and business logic not in the domain layer.
          if parent_issue&.global_relay_id != issue_attributes.parent_issue_id
            mutation = Platform.execute(
              (
                GraphQL.parse <<-'GRAPHQL'
                  mutation($input: AddSubIssueInput!) {
                    addSubIssue(input: $input) {
                      issue {
                        id
                      }
                      errors {
                        message
                      }
                    }
                  }
                GRAPHQL
              ),
              target: :internal,
              context: { viewer: current_user },
              variables: {
                "input" => {
                  "issueId" => issue_attributes.parent_issue_id,
                  "subIssueId" => issue.global_relay_id,
                  "replaceParent" => true,
                },
              },
            )

            if mutation.errors.any?
              raise Errors::ErrorParser.parse_graphql_error(mutation.errors, "Failed to reparent issue", repository.id, issue_tag: issue_attributes.tag)
            end
          end
        end

        CreatedIssue.new(
          global_relay_id: issue.global_relay_id,
          database_id: issue.id,
          title: issue.title,
          number: issue.number,
          url: issue.url,
          repository_id: repository.id,
          errors: nil,
          dependency_errors: dependency_errors[issue_attributes.tag],
        )
      end
    end

    sig { params(issue_id: String, issue_tag: String, projects: T::Array[Project], repository: Repository).void }
    def assign_issue_to_projects(issue_id, issue_tag, projects, repository)
      collect_metrics("copilot_issues.bulk_create.assign_issue_to_projects") do
        return if projects.empty? || repository.owner.nil?
        project_mappings = fetch_project_node_ids(projects, repository, issue_tag)

        project_mappings.each do |mapping|
          variables = {
            "input" => {
              "contentId" => issue_id,
              "projectId" => mapping[:id],
            },
          }

          mutation = Platform.execute(
            update_issue_projects_mutation,
            target: :internal,
            context: { viewer: current_user },
            variables: variables
          )

          if mutation.errors.any?
            T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(T.must(mapping[:title]), mutation.errors.map { |e| e["message"] })
          end
        end
      end
    end

    sig { returns(T::Hash[String, IssueNode]) }
    def build_draft_issue_tree_map
      collect_metrics("copilot_issues.bulk_create.build_draft_issue_tree_map") do
        tree_map = T.let(
          issues.each_with_object({}) do |issue_metadata, map|
            issue_attributes = fetch_issue_attributes(issue_metadata)

            map[issue_metadata.tag] = IssueNode.new(
              tag: issue_metadata.tag,
              item: issue_attributes,
              parent: nil,
              children: []
            )
          end,
          T::Hash[String, IssueNode]
        )

        issues.each do |issue_metadata|
          next unless issue_metadata.parent_tag

          parent_node = tree_map[T.must(issue_metadata.parent_tag)]
          current_node = tree_map[issue_metadata.tag]

          if parent_node && current_node
            current_node.parent = parent_node
            parent_node.children << current_node
          end
        end

        tree_map
      end
    end

    sig { returns(T::Hash[Integer, Repository]) }
    def unique_repositories
      repo_ids = issues.map(&:repository_id).uniq
      found_repositories = Repository.where(id: repo_ids).index_by(&:id)
      delta = repo_ids - found_repositories.keys
      raise Errors::ServiceError.new("Invalid repositories: #{delta.join(", ")}") if delta.any?

      found_repositories
    end

    sig { returns(GraphQL::Language::Nodes::Document) }
    def update_issue_projects_mutation
      GraphQL.parse <<-'GRAPHQL'
        mutation($input: AddProjectV2ItemByIdInput!)
        {
          addProjectV2ItemById(input: $input) {
            item {
              id
              databaseId
              type
              content {
                ... on Issue {
                  title
                  databaseId
                }
              }
            }
          }
        }
      GRAPHQL
    end

    sig { params(projects: T::Array[Project], repository: Repository, issue_tag: String).returns(T::Array[T::Hash[Symbol, String]]) }
    def fetch_project_node_ids(projects, repository, issue_tag)
      requested_project_titles = T.let([], T::Array[String])
      requested_project_ids = T.let([], T::Array[String])
      fetched_projects_by_id = T.let({}, T::Hash[String, String])

      projects.each do |project|
        # If project already has an ID, collect it for validation via node query
        if project.id.present?
          requested_project_ids << T.must(project.id)
          next
        end

        # Fall back to GraphQL lookup by title for legacy projects without IDs
        project_title = project.title
        next unless project_title.present?

        requested_project_titles << T.must(project_title).downcase
      end

      requested_project_titles.uniq!
      requested_project_ids.uniq!

      return [] if requested_project_ids.empty? && requested_project_titles.empty?

      requested_project_titles.each do |project_title|
        variables = {
          "owner" => repository.owner_display_login,
          "repo" => repository.name,
          "query" => project_title,
        }

        query = Platform.execute(
          projects_query,
          target: :internal,
          context: { viewer: current_user },
          variables: variables

        )

        if query.errors.any?
          T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(project_title, query.errors.map { |e| e["message"] })
          next
        end

        repo_projects = query.data["repository"]["projectsV2"]["nodes"]
        org_projects = query.data["repository"]["owner"]["projectsV2"]["edges"].map { |edge| edge["node"] }
        recent_repo_projects = query.data["repository"]["recentProjects"]["edges"].map { |edge| edge["node"] }
        recent_org_projects = query.data["repository"]["owner"]["recentProjects"]["edges"].map { |edge| edge["node"] }

        all_projects = repo_projects | org_projects | recent_repo_projects | recent_org_projects
        found_projects = all_projects
          .reject { |project| project["closed"] || project["hasReachedItemsLimit"] }
          .select { |project| project_title.downcase == project["title"].downcase }

        if found_projects.empty?
          T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(project_title, ["Project not found or inaccessible"])
          next
        end

        found_projects.map { |project| fetched_projects_by_id[project["id"]] = project["title"] }
      end

      # Validate project IDs by querying each node directly
      requested_project_ids.each do |project_id|
        query = Platform.execute(
          project_by_id_query,
          target: :internal,
          context: { viewer: current_user },
          variables: { "projectId" => project_id }
        )

        if query.errors.any?
          T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(project_id, query.errors.map { |e| e["message"] })
          next
        end

        project_node = query.data["node"]

        # Check if the node exists and is a ProjectV2
        if project_node.nil?
          T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(project_id, ["Project not found"])
          next
        end

        # Check if project is closed or has reached item limit
        if project_node["closed"] || project_node["hasReachedItemsLimit"]
          T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(project_id, ["Project is closed or has reached item limit"])
          next
        end

        # Verify the viewer has access (viewerCanUpdate indicates at least read access)
        unless project_node["viewerCanUpdate"] == true
          T.must(@errors[issue_tag]) << Errors::ProjectAssignmentError.new(project_id, ["No access to project"])
          next
        end

        fetched_projects_by_id[project_node["id"]] = project_node["title"]
      end

      fetched_projects = fetched_projects_by_id.map do |project_id, project_title|
        { id: project_id, title: project_title }
      end

      fetched_projects
    end

    sig { returns(GraphQL::Language::Nodes::Document) }
    def projects_query
      GraphQL.parse <<-'GRAPHQL'
        query($owner: String!, $repo: String!, $query: String) {
          repository(owner: $owner, name: $repo) {
            projectsV2(first: 5, query: $query, orderBy: {field: RELEVANCE, direction: DESC}, useFullTermQuery: true) {
              nodes {
                id
                title
                closed
                hasReachedItemsLimit
              }
            }
            recentProjects(first: 5) {
              edges {
                node {
                  id
                  title
                  closed
                  hasReachedItemsLimit
                }
              }
            }
            owner {
              ... on Organization {
                projectsV2(first: 5, orderBy: {field: RELEVANCE, direction: DESC}, query: $query, useFullTermQuery: true) {
                  edges {
                    node {
                      id
                      title
                      closed
                      hasReachedItemsLimit
                    }
                  }
                }
                recentProjects(first: 5) {
                  edges {
                    node {
                      id
                      title
                      closed
                      hasReachedItemsLimit
                    }
                  }
                }
              }
              ... on User {
                projectsV2(first: 5, orderBy: {field: RELEVANCE, direction: DESC}, query: $query, useFullTermQuery: true) {
                  edges {
                    node {
                      id
                      title
                      closed
                      hasReachedItemsLimit
                    }
                  }
                }
                recentProjects(first: 5) {
                  edges {
                    node {
                      id
                      title
                      closed
                      hasReachedItemsLimit
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end

    sig { returns(GraphQL::Language::Nodes::Document) }
    def project_by_id_query
      GraphQL.parse <<-'GRAPHQL'
        query($projectId: ID!) {
          node(id: $projectId) {
            ... on ProjectV2 {
              id
              title
              closed
              hasReachedItemsLimit
              viewerCanUpdate
            }
          }
        }
      GRAPHQL
    end

    sig { params(metadata: IssueMetadata).returns(IssueAttributes) }
    def fetch_issue_attributes(metadata)
      repository = T.must(repositories[T.must(metadata.repository_id)])

      if metadata.is_a?(ExistingIssueMetadata)
        return ExistingIssueAttributes.new(
          tag: metadata.tag,
          repository:,
          number: metadata.number,
          blocked_by_tags: metadata.blocked_by_tags,
          parent_issue_id: nil,
          agent_assignment: metadata.agent_assignment,
        )
      end

      issue_type = fetch_issue_type(metadata.issue_type, repository)
      labels = fetch_labels(metadata.labels, T.must(metadata.repository_id))
      milestone = fetch_milestone(metadata.milestone, repository)
      assignees = fetch_assignees(metadata.assignees)
      template_name = fetch_template(metadata.template, repository, current_user, metadata.tag)&.name
      project_titles = T.let([], T::Array[String])
      projects = T.let([], T::Array[Project])

      # Separate project titles and normalized projects
      projects_to_process = metadata.projects
      projects_to_process.each do |project|
        case project
        when String
          project_titles << project
        when Project
          projects << project
        end
      end

      issue_field_attributes = prepare_issue_fields(metadata.issue_fields)

      DraftIssueAttributes.new(
        tag: metadata.tag,
        title: metadata.title,
        repository: repository,
        body: metadata.body,
        issue_type: T.cast(issue_type, T.nilable(IssueType)),
        labels: T.cast(labels, T::Array[Label]),
        milestone: T.cast(milestone, T.nilable(Milestone)),
        assignees: T.cast(assignees, T::Array[User]),
        template_name: template_name,
        project_titles: project_titles,
        projects: projects,
        blocked_by_tags: metadata.blocked_by_tags,
        agent_assignment: metadata.agent_assignment,
        issue_fields: issue_field_attributes,
      )
    end

    sig { params(issue_type_name: T.nilable(String), repository: Repository).returns(T.nilable(Issues::IIssueType)) }
    def fetch_issue_type(issue_type_name, repository)
      return if issue_type_name.nil?
      return unless repository.owner&.organization?

      Issues.domain.issue_types.by_organization_and_name(T.cast(repository.owner, Orgs::IOrganization), issue_type_name)
    end

    sig { params(label_names: T::Array[String], repository_id: Integer).returns(T::Array[Issues::ILabel]) }
    def fetch_labels(label_names, repository_id)
      return [] if label_names.empty?

      Issues.domain.labels.by_repository_and_names(
        repository_id:,
        names: label_names
      )
    end

    sig { params(milestone_name: T.nilable(String), repository: Repository).returns(T.nilable(Issues::IMilestone)) }
    def fetch_milestone(milestone_name, repository)
      return if milestone_name.nil?

      repository.milestones.find_by(title: milestone_name)
    end

    sig { params(assignee_logins: T::Array[String]).returns(T::Array[Users::IUser]) }
    def fetch_assignees(assignee_logins)
      return [] if assignee_logins.empty?

      User.where(login: assignee_logins).to_a
    end

    sig { params(template_filename: T.nilable(String), repository: Repository, user: User, issue_tag: String).returns(T.nilable(IssueTemplate)) }
    def fetch_template(template_filename, repository, user, issue_tag)
      return if template_filename.nil?

      template = repository.preferred_issue_templates(user)[template_filename]
      T.must(@errors[issue_tag]) << Errors::TemplateParsingError.new(template_filename, ["Invalid template"]) if template.nil?

      template
    end

    sig { params(agent_assignment_hash: T.nilable(T::Hash[T.any(String, Symbol), T.nilable(String)])).returns(T.nilable(AgentAssignmentAttributes)) }
    def parse_agent_assignment(agent_assignment_hash)
      return nil if agent_assignment_hash.nil?

      agent_assignment_hash = agent_assignment_hash.with_indifferent_access
      AgentAssignmentAttributes.new(
        target_repo: agent_assignment_hash[:target_repo],
        base_ref: agent_assignment_hash[:base_ref],
        custom_instructions: agent_assignment_hash[:custom_instructions],
        custom_agent: agent_assignment_hash[:custom_agent]
      )
    end

    sig { params(issue_fields_array: T.nilable(T::Array[T::Hash[T.any(String, Symbol), T.untyped]])).returns(T::Array[IssueFieldInput]) }
    def parse_issue_fields(issue_fields_array)
      return [] if issue_fields_array.blank?

      issue_fields_array.filter_map do |field_hash|
        field_hash = field_hash.with_indifferent_access
        next if field_hash[:field_id].blank?

        IssueFieldInput.new(
          field_id: field_hash[:field_id],
          text_value: field_hash[:text_value],
          single_select_option_id: field_hash[:single_select_option_id],
          date_value: field_hash[:date_value],
          number_value: field_hash[:number_value]&.to_f,
        )
      end
    end

    sig { params(issue_field_inputs: T::Array[IssueFieldInput]).returns(T.nilable(T::Array[IssueField::IssueFieldAttributesType])) }
    def prepare_issue_fields(issue_field_inputs)
      return nil if issue_field_inputs.empty?

      issue_field_inputs.map do |issue_field_input|
        _, issue_field_database_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field_input.field_id)

        if issue_field_input.text_value
          Issues::IssueFieldTextValueAttributes.new(
            field_id: issue_field_database_id.to_i,
            text_value: T.must(issue_field_input.text_value)
          )
        elsif issue_field_input.single_select_option_id
          _, issue_field_option_database_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field_input.single_select_option_id)
          Issues::IssueFieldSingleSelectValueAttributes.new(
            field_id: issue_field_database_id.to_i,
            option_id: issue_field_option_database_id&.to_i
          )
        elsif issue_field_input.date_value
          Issues::IssueFieldDateValueAttributes.new(
            field_id: issue_field_database_id.to_i,
            date_value: T.must(issue_field_input.date_value)
          )
        elsif issue_field_input.number_value
          Issues::IssueFieldNumberValueAttributes.new(
            field_id: issue_field_database_id.to_i,
            number_value: T.must(issue_field_input.number_value)
          )
        else
          raise Errors::ValidationOrAccessError.new(
            "Issue field '#{issue_field_input.field_id}' has no supported value. " \
            "You must provide a text_value, single_select_option_id, date_value, or number_value."
          )
        end
      end
    end
  end
end
