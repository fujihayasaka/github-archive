# typed: true
# frozen_string_literal: true

class Issue
  class Builder
    include Issues::Domain::Provider

    def initialize(user, repository)
      @user = user
      @repository = repository
    end

    # Construct an instance of the Issue model for the builder's User and Respository
    # Expects parameters to be in the format supplied by the view, and
    # handles the various legacy param formats we support all over the site
    #
    # Returns a populated but unsaved Issue object
    def build(unsafe_params)
      unsafe_issue_params = unsafe_params.fetch :issue, {}
      unsafe_params[:title] = unsafe_issue_params[:title]
      unsafe_params[:body] = unsafe_issue_params[:body]

      allowed_keys = [
        :repository_id,
        :user_id,
        :title,
        :body,
      ]

      safe_issue_params = unsafe_params.slice(*allowed_keys).
        reverse_merge(repository_id: @repository.id)

      owner = @repository.owner
      issue = @repository.issues.build safe_issue_params
      issue.user = @user

      if issue.can_set_milestone?(@user)
        if milestone = unsafe_params[:milestone]
          issue.milestone = @repository.milestones.find_by_id(milestone)
        end
      end

      issue.issue_type = if issue.can_set_type?(actor: @user) && owner.issue_types_enabled?
        owner.issue_types.find_by(id: unsafe_issue_params[:issue_type_id])
      else
        nil
      end

      user_can_label = issue.labelable_by?(actor: @user)
      if user_can_label
        if labels = unsafe_issue_params[:labels]
          issue.labels = if GitHub.flipper[:issue_dependency_removal].enabled?
            issues_domain.labels.by_repository_and_normalized_ids(repository_id: @repository.id, label_ids: labels)
          else
            @repository.load_labels(labels)
          end
        end

        if label_ids = unsafe_issue_params[:label_ids]
          issue.labels = @repository.labels.where(id: label_ids)
        end
      end

      user_can_assign = issue.assignable_by?(actor: @user)
      assignees = []
      if user_can_assign
        if assignee_login = unsafe_issue_params[:assignee]
          assignees = [User.find_by_login(assignee_login)]
        end

        if assignee_id = unsafe_issue_params[:assignee_id]
          assignees = [User.find_by(id: assignee_id)]
        end

        # This param is named `user_assignee_ids` to make things easier if
        # we ever want to do team assignees as well.
        if user_assignee_ids = unsafe_issue_params[:user_assignee_ids]
          assignees = User.where(id: user_assignee_ids)
        end

        issue.assignees = assignees
      end

      if unsafe_issue_params[:body_template_name].present?
        issue.body_template_name = unsafe_issue_params[:body_template_name]
      end

      if issue.body_template_name.present?
        build_from_template(issue, unsafe_params, user_can_label, user_can_assign)
      end

      if issue_project_ids = unsafe_params[:issue_project_ids]
        projects = issue.potential_projects_for(@user, ids: issue_project_ids.keys)
        GitHub.dogstats.count("pending_card.created_during_issue_creation", projects.size)

        projects.each do |project|
          if issue_project_ids[project.id.to_s] == "on"
            # We can set content directly here because the user is creating the issue,
            # so we know they have access to it
            issue.cards.build(creator: @user, project: project, content: issue)
          end
        end
      end

      issue
    end

    def build_from_api(data)
      issue = @repository.issues.build
      issue.title = data["title"]
      issue.body = data["body"]
      issue.user = @user
      issue.labels = data["labels"] if data["labels"]

      issue
    end

    private

    def build_from_template(issue, params, user_can_label, user_can_assign)
      template = T.let(nil, T.nilable(IssueTemplate))

      if GitHub.flipper[:build_from_template__use_read_replica].enabled?(@user)
        ActiveRecord::Base.connected_to(role: :reading) do
          template = issue.template
        end
      else
        template = issue.template
      end

      return unless template.present?

      issue.labels = @repository.labels.merge(Label.with_name(template.labels.map(&:name))) unless user_can_label
      issue.assignees = template.assignees unless user_can_assign

      if template.structured?
        issue_form_response_builder = StructuredTemplates::BodyBuilder.new(
          template: template,
          form_params: params[:issue_form],
          templatable: issue,
        )

        if issue_form_response_builder.valid?
          issue.body = issue_form_response_builder.to_markdown
          issue.issue_form_params = issue_form_response_builder.form_params
        end
      end
    end
  end
end
