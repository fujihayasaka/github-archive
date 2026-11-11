# typed: true
# frozen_string_literal: true

class Codespaces::CodeMenuCodespacesListComponent < ApplicationComponent
  attr_reader :visibility, :pull_request, :repository, :ref, :name_param

  def initialize(visibility:, pull_request:, repository:, name_param:, ref:)
    @visibility = visibility
    @pull_request = pull_request
    @repository = repository
    @name_param = name_param
    @ref = ref
  end

  def pull_request?
    !!pull_request
  end

  def current_branch_or_tag_name
    return if pull_request?

    if name_param.blank?
      repository.default_branch
    elsif repository.refs.exist?(name_param)
      name_param
    end
  end

  def codespaces_path_params
    if !pull_request?
      {
        event_target: "REPO_PAGE",
        repo: repository.id,
        current_branch: current_branch_or_tag_name,
        codespace: { ref: ref },
      }
    else
      missing_head_repo = pull_request.cross_repo? && !pull_request.head_repository
      missing_head_ref = visibility.can_see_codespaces_for_pull_request? &&
          pull_request.closed? &&
          !pull_request.head_ref_exist?

      {
        event_target: "PULL_REQUEST_PAGE_DROPDOWN",
        repo: repository.id,
        current_branch: pull_request.display_head_ref_name,
        codespace: { pull_request_id: pull_request.id },
        pr_dropdown: true,
        missing_head_repo: missing_head_repo,
        missing_head_ref: missing_head_ref,
      }
    end
  end
end
