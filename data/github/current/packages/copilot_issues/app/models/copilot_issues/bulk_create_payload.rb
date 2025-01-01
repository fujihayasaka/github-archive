# typed: true
# frozen_string_literal: true

module CopilotIssues
  class BulkCreatePayload
    include CopilotIssues::Metrics

    # *IssueMetadata represents the payload from the client to create issues in bulk.
    IssueMetadata = T.type_alias { T.any(DraftIssueMetadata, ExistingIssueMetadata) }

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
      const :projects, T::Array[String]
    end

    class ExistingIssueMetadata < T::Struct
      const :tag, String
      const :parent_tag, T.nilable(String)
      const :repository_id, Integer
      const :number, Integer
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
      const :project_titles, T::Array[String]
      prop :parent_issue_id, T.nilable(String), default: nil
    end

    class ExistingIssueAttributes < T::Struct
      const :tag, String
      const :repository, Repository
      const :number, Integer
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
      const :errors, T.nilable(T::Array[String])
    end

    class IssueCreationError < StandardError
      sig do
        params(
          message: String,
          repository_id: T.nilable(Integer),
          issue_tag: T.nilable(String),
          errors: T.nilable(T::Array[T::Hash[String, T.untyped]])
        ).void
      end
      def initialize(message, repository_id: nil, issue_tag: nil, errors: nil)
        super(message)
        @repository_id = repository_id
        @issue_tag = issue_tag
        @errors = errors
      end

      attr_reader :repository_id, :issue_tag, :errors
    end

    sig { returns(T::Array[IssueMetadata]) }
    attr_reader :issues

    sig { returns(T::Hash[String, IssueNode]) }
    attr_reader :draft_issue_tree_map

    sig { returns(T::Hash[Integer, Repository]) }
    attr_reader :repositories

    sig { returns(User) }
    attr_reader :current_user

    sig { returns(T::Array[String]) }
    attr_reader :errors

    sig { params(issues_payload: T::Array[T::Hash[String, T.untyped]], current_user: User).void }
    def initialize(issues_payload, current_user)
      @current_user = T.let(current_user, User)

      @issues = issues_payload.map do |metadata|
        metadata = metadata.with_indifferent_access

        if metadata[:number].present?
          ExistingIssueMetadata.new(
            tag: metadata[:tag],
            parent_tag: metadata[:parent_tag],
            repository_id: metadata[:repository_id].to_i,
            number: metadata[:number].to_i,
          )
        else
          DraftIssueMetadata.new(
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
            projects: metadata[:projects] || [],
          )
        end
      end
      @repositories = T.let(unique_repositories, T::Hash[Integer, Repository])
      @draft_issue_tree_map = T.let(build_draft_issue_tree_map, T::Hash[String, IssueNode])
      @errors = T.let([], T::Array[String])
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

    private

    sig { params(errors: T::Array[T::Hash[String, T.untyped]], action_message: String, repository_id: Integer, issue_tag: T.nilable(String)).void }
    def parse_and_raise_graphql_error(errors, action_message, repository_id, issue_tag: nil)
      graphql_error_message = T.must(errors[0]).dig("message") || "Unknown error"
      raise IssueCreationError.new("#{action_message}. #{graphql_error_message}", repository_id:, issue_tag:, errors:)
    end

    sig { params(issue_attributes: DraftIssueAttributes, repository: Repository).returns(CreatedIssue) }
    def create_issue(issue_attributes, repository)
      collect_metrics("copilot_issues.bulk_create.create_issue_with_issues_domain") do
        parent_issue = if issue_attributes.parent_issue_id
          parsed = Platform::Helpers::GlobalId.parse(issue_attributes.parent_issue_id)
          case parsed
          when Platform::Helpers::GlobalId::Next
            Platform::Objects::Issue.load_from_next_global_id(parsed)
          else
            Platform::Objects::Issue.load_from_global_id(parsed)
          end.sync
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
          parent_issue: parent_issue
        )

        if !repository.writable_by?(current_user)
          raise IssueCreationError.new("User #{current_user.id} cannot create issues in repo", repository_id: repository.id)
        end

        result = Issues.domain.create(create_issue_attributes, current_user, viewer: current_user)

        if (issue = result.ok)
          global_relay_id = T.cast(issue, ::Issue).global_relay_id

          if issue_attributes.project_titles.any?
            assign_issue_to_projects(global_relay_id, issue_attributes.project_titles, repository)
          end

          CreatedIssue.new(
            global_relay_id: global_relay_id,
            database_id: T.must(issue.id),
            title: issue.title,
            number: issue.number.to_i,
            url: issue.permalink,
            repository_id: repository.id,
            errors: errors,
          )
        else
          error = T.must(result.error)
          raise IssueCreationError.new("Issue creation failed. #{error.message}", repository_id: repository.id, issue_tag: issue_attributes.tag)
        end
      end
    end

    sig { params(issue_attributes: ExistingIssueAttributes, repository: Repository).returns(CreatedIssue) }
    def fetch_and_reparent_existing_issue(issue_attributes, repository)
      collect_metrics("copilot_issues.bulk_create.fetch_existing_issue") do
        issue = Issues.domain.by_number(issue_attributes.number, repo_id: repository.id)
        raise "Issue not found" if issue.nil?
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
              parse_and_raise_graphql_error(mutation.errors, "Failed to reparent issue", repository.id, issue_tag: issue_attributes.tag)
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
        )
      end
    end

    sig { params(issue_id: String, projects: T::Array[String], repository: Repository).void }
    def assign_issue_to_projects(issue_id, projects, repository)
      collect_metrics("copilot_issues.bulk_create.assign_issue_to_projects") do
        return if projects.empty? || repository.owner.nil?
        project_mappings = fetch_project_node_ids(projects, repository)

        if project_mappings.length != projects.length
          @errors << "Some projects not found or inaccessible in repository #{repository.name_with_display_owner}"
        end

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

          @errors << mutation.errors.map { |e| e["message"] }.join(", ") if mutation.errors.any?
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
      raise IssueCreationError.new("Invalid repositories: #{delta.join(", ")}") if delta.any?

      found_repositories
    end

    sig { returns(GraphQL::Language::Nodes::Document) }
    def create_issue_mutation
      GraphQL.parse <<-'GRAPHQL'
        mutation($input: CreateIssueInput!) {
          createIssue(input: $input) {
            issue {
              databaseId
              repository {
                databaseId
              }
              title
              id
              number
              url
            }
            errors {
              message
            }
          }
        }
      GRAPHQL
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

    sig { params(projects: T::Array[String], repository: Repository).returns(T::Array[T::Hash[Symbol, String]]) }
    def fetch_project_node_ids(projects, repository)
      fetched_projects = T.let([], T::Array[T::Hash[Symbol, String]])
      requested_projects = projects.map(&:downcase).uniq

      requested_projects.each do |project_title|
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
          @errors << query.errors.map { |e| e["message"] }.join(", ")
          next
        end

        repo_projects = query.data["repository"]["projectsV2"]["nodes"]
        org_projects = query.data["repository"]["owner"]["projectsV2"]["edges"].map { |edge| edge["node"] }
        recent_repo_projects = query.data["repository"]["recentProjects"]["edges"].map { |edge| edge["node"] }
        recent_org_projects = query.data["repository"]["owner"]["recentProjects"]["edges"].map { |edge| edge["node"] }

        all_projects = repo_projects | org_projects | recent_repo_projects | recent_org_projects
        found_projects = all_projects
          .reject { |project| project["closed"] || project["hasReachedItemsLimit"] }
          .select { |project| requested_projects.include?(project["title"].downcase) }

        fetched_projects << found_projects.map { |project| { id: project["id"], title: project["title"] } }.compact
      end

      fetched_projects.flatten
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

    sig { params(metadata: IssueMetadata).returns(IssueAttributes) }
    def fetch_issue_attributes(metadata)
      repository = T.must(repositories[T.must(metadata.repository_id)])

      if metadata.is_a?(ExistingIssueMetadata)
        return ExistingIssueAttributes.new(
          tag: metadata.tag,
          repository:,
          number: metadata.number,
          parent_issue_id: nil
        )
      end

      issue_type = fetch_issue_type(metadata.issue_type, repository)
      labels = fetch_labels(metadata.labels, T.must(metadata.repository_id))
      milestone = fetch_milestone(metadata.milestone, repository)
      assignees = fetch_assignees(metadata.assignees)
      template_name = fetch_template(metadata.template, repository, current_user)&.name

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
        project_titles: metadata.projects
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

    sig { params(template_filename: T.nilable(String), repository: Repository, user: User).returns(T.nilable(IssueTemplate)) }
    def fetch_template(template_filename, repository, user)
      return if template_filename.nil?

      repository.preferred_issue_templates(user)[template_filename]
    end
  end
end
