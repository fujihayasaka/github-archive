# typed: true
# frozen_string_literal: true

class Repos::AgentSessionsBaseController < AbstractRepositoryController
  before_action :login_required
  before_action :require_copilot_swe_agent_enabled
  before_action :load_current_pull_request

  attr_reader :pull

  private

  def load_current_pull_request
    begin
      @pull = PullRequests::PullRequestAccessor.new.by_number(repository_id: current_repository.id, number: params[:pull_number].to_i)
    rescue GH::Errors::ObjectNotFound
      render_404
    end
  end

  def require_copilot_swe_agent_enabled
    render_404 unless current_repository.copilot_swe_agent_enabled?(current_user)
  end
end
