# typed: false
# frozen_string_literal: true

class Community::CommunityIndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include UrlHelper
  include EscapeHelper

  attr_reader :community_profile
  attr_reader :repository

  delegate :code_of_conduct?, :sufficient_code_of_conduct?, :code_of_conduct_path,
     :readme?, :contributing?, :license?, :description?, :pr_or_issue_template?,
     :health_percentage, :health_progress, :issue_template, :pr_template, :issue_template?,
     :tiered_reporting_enabled?, to: :community_profile

  INDICATORS = {
    positive: { octicon: "check", class: "mr-1 color-fg-success", label: "Added" },
    negative: { octicon: "dot-fill", class: "mr-1 checklist-dot", label: "Not added yet" },
  }.freeze

  def show_calls_to_action?
    return @show_calls_to_action if defined?(@show_calls_to_action)
    @show_calls_to_action = logged_in? && !current_user.is_enterprise_managed?
  end

  def empty_file?(file)
    file && file.data.blank?
  end

  def readme_indicators
    indicator_for_display(readme?)
  end

  def readme_file
    repository.preferred_readme
  end

  def has_empty_readme?
    empty_file?(readme_file)
  end

  def license_indicators
    indicator_for_display(license?)
  end

  def code_of_conduct_indicators
    indicator_for_display(sufficient_code_of_conduct?)
  end

  def has_empty_code_of_conduct?
    empty_file?(repository.preferred_code_of_conduct)
  end

  def code_of_conduct_path
    return nil unless code_of_conduct?
    @coc_path ||= preferred_file_path(
      type: :code_of_conduct,
      repository: repository,
    )
  end

  def contributing_indicators
    indicator_for_display(contributing?)
  end

  def contributing_file
    repository.preferred_contributing
  end

  def has_empty_contributing?
    empty_file?(contributing_file)
  end

  def description_indicators
    indicator_for_display(description?)
  end

  def security_policy_indicators
    indicator_for_display(security_policy?)
  end

  def issue_template_indicator
    indicator_for_display(has_issue_templates?)
  end

  def security_policy
    repository.preferred_files.fetch(:security)
  end

  def security_policy?
    security_policy.present?
  end

  def has_issue_templates?
    repository.preferred_issue_templates.any?
  end

  def has_legacy_template?
    repository.preferred_issue_templates.templates_with_legacy.any?
  end

  # Public: Is a user able to edit the issue templates for this repository?
  #
  # user - The User to check.
  #
  # Returns a Boolean.
  def issue_template_editable_by?(user)
    return false unless user.present?
    repository.preferred_issue_templates.repository.pushable_by?(user)
  end

  # Public: Generate the link to edit or add issue templates.
  #
  # Returns a String.
  def issue_template_edit_link
    templates = repository.preferred_issue_templates
    repo = templates.repository
    branch = repo.default_branch
    directory = IssueTemplates.template_directory
    text = has_issue_templates? ? "Edit" : "Add"

    path = urls.edit_issue_templates_path(repo.owner, repo)

    helpers.link_to(text, path, class: "btn btn-sm")
  end

  def pull_request_template_indicator
    indicator_for_display(has_pull_request_template?)
  end

  def has_pull_request_template?
    community_profile.pr_template.present?
  end

  # Public: Is a user able to edit the pull request template for this repository?
  #
  # user - The User to check.
  #
  # Returns a Boolean.
  def pull_request_template_editable_by?(user)
    return false unless user.present? && pr_template_file.present?
    pr_template_file.repository.pushable_by?(user)
  end

  def pr_template_file
    repository.preferred_pull_request_template
  end

  def has_empty_pull_request_template?
    empty_file?(pr_template_file)
  end

  def template_indicators
    indicator_for_display(pr_or_issue_template?)
  end

  def link_to_pull_request_template
    helpers.link_to(
      "Pull request template",
      blob_view_url(pr_template.path, pr_template.repository.default_branch, pr_template.repository),
    )
  end

  def links_to_templates
    if issue_template && pr_template
      safe_join(
        [
          helpers.link_to(
            "Issue template",
            blob_view_url(issue_template.path, issue_template.repository.default_branch, issue_template.repository),
          ),
          link_to_pull_request_template,
        ],
        " and ",
      )
    elsif issue_template
      helpers.link_to(
        "Issue template",
        blob_view_url(issue_template.path, issue_template.repository.default_branch, issue_template.repository),
      )
    elsif pr_template
      helpers.link_to(
        "Pull request template",
        blob_view_url(pr_template.path, pr_template.repository.default_branch, pr_template.repository),
      )
    end
  end

  def button_copy
    @button_copy ||= repository.pushable_by?(current_user) ? "Add" : "Propose"
  end

  def can_add_description?
    repository.pushable_by?(current_user)
  end

  def can_enable_tiered_reporting?
    repository.can_enable_tiered_reporting?(current_user)
  end

  def tiered_reporting_indicator
    indicator_for_display(tiered_reporting_enabled?)
  end

  private

  def indicator_for_display(condition)
    condition ? INDICATORS[:positive] : INDICATORS[:negative]
  end
end
