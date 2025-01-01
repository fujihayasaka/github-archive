# typed: true
# frozen_string_literal: true

module Api::App::ActionsUrlHelper
  extend T::Helpers
  requires_ancestor { Api::App }

  def runners_api_path_for_runner_owner(runner_owner)
    if runner_owner.is_a?(Organization)
      "/orgs/#{runner_owner.display_login}/actions/runners"
    elsif runner_owner.is_a?(Business)
      "/enterprises/#{runner_owner.to_param}/actions/runners"
    elsif runner_owner.is_a?(Repository)
      "/repos/#{runner_owner.name_with_owner_for_api}/actions/runners"
    end
  end

  def runners_url_for_runner_owner(runner_owner)
    "#{GitHub.api_url}#{runners_api_path_for_runner_owner(runner_owner)}"
  end

  def runners_back_compat_url_for_runner_owner(runner_owner)
    "#{runners_url_for_runner_owner(runner_owner)}/_shim"
  end
end
