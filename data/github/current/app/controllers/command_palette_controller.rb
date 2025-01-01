# typed: true
# frozen_string_literal: true

class CommandPaletteController < ApplicationController

  before_action :login_required
  before_action :ensure_command_palette_enabled
  before_action :require_xhr
  before_action :load_scope
  before_action :load_subject

  protected

  def ensure_command_palette_enabled
    return if helpers.command_palette_enabled?
    render_404
  end

  def return_to
    return_to_params = {
      command_palette_open: true,
      command_mode: params[:mode],
      command_query: query
    }

    return_to_params[:clear_command_scope] = true if scope.blank?
    joiner = params[:return_to] && params[:return_to].include?("?") ? "&" : "?"

    "#{params[:return_to]}#{joiner}#{return_to_params.to_param}"
  end

  memoize def load_scope
    return if params[:scope].blank?

    type, id = Platform::Helpers::NodeIdentification.from_global_id(params[:scope])
    possible_scope =
      case type
      when "User", "Organization" then User.find(id)
      when "Repository" then Repositories::Public.find_active!(id)
      when "Issue" then Issue.find(id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      when "PullRequest" then PullRequest.find(id)
      when "Discussion" then Discussion.find(id)
      when "MemexProject", "ProjectV2" then MemexProject.find(id)
      end

    if accessible_subject?(possible_scope)
      @scope = possible_scope
    else
      render_404
    end
  end

  memoize def load_subject
    return if params[:subject].blank?

    type, id = Platform::Helpers::NodeIdentification.from_global_id(params[:subject])
    possible_subject =
      case type
      when "User", "Organization" then User.find(id)
      when "Repository" then Repositories::Public.find_active!(id)
      when "Issue" then Issue.find(id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      when "PullRequest" then PullRequest.find(id)
      when "Discussion" then Discussion.find(id)
      when "MemexProject", "ProjectV2" then MemexProject.find(id)
      end

    if accessible_subject?(possible_subject)
      @subject = possible_subject
    else
      render_404
    end
  end

  # Check if an object can be used as a subject to the current user as a subject.
  def accessible_subject?(subject)
    case subject
    when User then !subject.hide_from_user?(current_user)
    when Repository, Issue, PullRequest, MemexProject, Discussion then subject.readable_by?(current_user)
    when nil then true
    else
      false
    end
  end

  def scope
    @scope
  end

  def subject
    @subject
  end

  def query
    params[:q].to_s
  end

  def target_for_conditional_access
    load_subject
    load_scope

    entity = subject || scope

    # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    return :no_target_for_conditional_access unless entity
    # rubocop:enable GitHub/SpecifyTargetForConditionalAccess

    entity.target_for_conditional_access
  end

  def perform_conditional_access_checks
    # Always render a 404 if any of the policies are unsatisfied (i.e. don't redirect)
    results = cap_enforcer.evaluate_conditional_access_policies(target_for_conditional_access)
    render_404 if results.any? { |_policy, result| result == :unsatisfied }
  end
end
