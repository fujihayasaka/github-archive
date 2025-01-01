# typed: true
# frozen_string_literal: true

# This controller is used to defer the loading of information
# about the use of dependencies. It fits the batch deferred
# interface which expects an input (except x-www-form-urlencoded):
#
#   items: {
#     item-0: { dependency_id: 1 },
#     item-1: { dependency_id: 2 },
#   }
#
# and returns a JSON response of key/HTML pairs:
#
#   {
#     item-0: "<div>...</div>",
#     item-1: "<div>...</div>"
#   }
#
# that will replace DOM elements with the rendered HTML.
#
# See https://github.com/orgs/github/teams/engineering/discussions/301
# for more information.
class Sponsors::DependencyUsesController < ApplicationController
  include Sponsors::SharedDependenciesControllerMethods

  before_action :login_required
  before_action :sponsors_required
  before_action :require_allowed_filter_org_if_given

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:index]

  def index
    owner = filter_org || current_user
    loader = ::Repository::RepositoriesUsingDependenciesLoader.new(owner_id: owner.id, dependency_ids: dependency_ids)
    usage_counts_by_dependency = loader.async_usage_counts_by_dependency(
      viewer: current_user
    ).sync

    respond_to do |format|
      format.json do
        render json: keyed_response(usage_counts_by_dependency)
      end
    end
  end

  private

  # Private: Returns a hash of dependency_id => key used to map responses
  # from the dependency graph API to the appropriate key used by the batch
  # deferred system.
  memoize def keys_by_dependency_id
    items = params.require(:items).permit!.to_h
    items.each_with_object({}) do |(key, inputs), memo|
      dependency_id = inputs.fetch(:dependency_id).to_i
      memo[dependency_id] = key
    end
  end

  # Private: Returns an Array of Integer Repository IDs.
  memoize def dependency_ids
    keys_by_dependency_id.keys
  end

  # Private: Returns a hash of key => rendered HTML where the key is used
  # by the batch deferred system to replace an element in the DOM with the
  # appropriate rendered HTML.
  #
  # usage_counts_by_dependency - a Hash[Repository] => Integer. The keys are the dependencies and the values are
  #                              the counts of the repositories using the dependency.
  #
  # Returns a Hash of key => rendered HTML String.
  def keyed_response(usage_counts_by_dependency)
    usage_counts_by_dependency.each_with_object({}) do |(dependency, count), memo|
      key = keys_by_dependency_id.fetch(dependency.id)
      memo[key] = counts_html(count, dependency)
    end
  end

  def counts_html(count, dependency)
    whose_repos = filter_org ? "#{filter_org}'s" : "your"
    verb = count == 1 ? "depends" : "depend"
    account_login = filter_org&.login
    account_login ||= current_user.login

    render_to_string(
      partial: "sponsors/dependency_uses/dependent_repos_count",
      layout: false,
      formats: :html,
      locals: {
        count: count,
        whose_repos: whose_repos,
        verb: verb,
        dependency: dependency,
        account_login: account_login,
      }
    )
  end
end
