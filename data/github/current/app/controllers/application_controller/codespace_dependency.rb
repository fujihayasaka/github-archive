# typed: true
# frozen_string_literal: true

module ApplicationController::CodespaceDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  include ApplicationController::CodespaceTagActionDependency
  include CodespacesHelper
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    javascript_bundle :codespaces

    before_action :login_required
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    codespace = current_codespace(scoped_to_user: false)
    return self unless codespace
    codespace
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless current_repo # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    Codespaces::RepositoryPolicy.async_with_prefill(current_user, current_repo).sync.billable_owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  private

  def set_path_and_name
    return if @set_path_and_name
    @set_path_and_name = true

    return if params[:name].blank? || !params[:path].blank?
    return if current_repo.nil?

    branch, path, qualified_name = ref_sha_path_extractor.call(params[:name])

    # just leave the entire path in params[:name] if it didn't find anything,
    # as there seems to be some logic that might depend on this
    if branch
      # Set `branch` so we can distinguish when the `name` param is a user-given invalid
      # branch versus an existing branch.
      params[:branch] = branch

      params[:name] = branch
      params[:ref] = branch
      params[:path] = path.split("/") if path
      params[:qualified_name] = qualified_name
    end
  end

  def codespace_params
    allowed_params = %i(repository_id template_repository_id ref ref_name pull_request_id geo location vscs_target vscs_target_url sku_name devcontainer_path issue_id)
    params.require(:codespace).permit(*allowed_params)
  end

  def current_repo
    return @current_repo if defined?(@current_repo)

    @current_repo = case
    when params[:user_id].present? && params[:repository].present?
      Repository.nwo("#{params[:user_id]}/#{params[:repository]}")
    when params[:repo].nil?
      codespace_repo_id = params.dig(:codespace, :repository_id)
      codespace_repo_id && Repository.active.find_by(id: codespace_repo_id)

      # Integer checker before we unnecessarily query with Repository.find_by_id/1
    when params[:repo].match?(/\A\d+\z/)
      Repository.active.find_by(id: params[:repo])

      # "/" exists check before we unnecessarily query with Repository.nwo/1
    when params[:repo].include?("/")
      Repository.nwo(params[:repo])
    end
  end

  def require_feature_for_any_repo
    render_404 unless current_user&.codespaces_feature_enabled?
  end

  def require_feature_for_current_repo
    repo = case
    when current_repository
      current_repository
    when current_codespace
      current_codespace.repository
    when params.has_key?(:codespace) && codespace_params.has_key?(:repository_id)
      Repositories::Public.find_active!(codespace_params[:repository_id])
    when params.has_key?(:repo)
      Repositories::Public.find_active!(params[:repo])
    else
      nil
    end
    return render_404 unless repo

    repo_policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repo).sync
    render_404 unless repo_policy.can_attempt_create?
  end

  def require_codespace
    render_404 unless current_codespace
  end

  def verify_authorization
    render_404 unless current_codespace.owner == current_user && current_codespace.writable_by?(current_user)
  end

  def set_codespace_context
    Codespaces::ErrorReporter.push(codespace: current_codespace)
  end

  def usage_allowed?
    return unless current_codespace.billable_owner

    usage_result = codespace_usage(current_codespace)
    return if usage_result.allowed?

    flash[:error] = if usage_result.disallowed_by_spending_limit?
      "Oh no, you're over your spending limit for that codespace!"
    elsif usage_result.disallowed_by_payment_method?
      "Oh no, there seems to be a problem with your payment method!"
    elsif usage_result.disallowed_by_machine_policy?
      "This codespace is currently using a machine type disallowed by your organization settings. Please update the codespace's machine type or export your changes to a branch."
    end

    redirect_to codespaces_path and return
  end

  def identifier
    raise "must be overridden in including class to use current_codespace"
  end

  def current_codespace(scoped_to_user: true)
    return unless identifier && logged_in?
    return @current_codespace if defined?(@current_codespace)
    scope = scoped_to_user ? current_user.codespaces : Codespace

    @current_codespace = scope.find_by(name: identifier) || scope.find_by(guid: identifier)
  end

  memoize def ref_sha_path_extractor
    GitHub::RefShaPathExtractor.new(current_repo)
  end
end
