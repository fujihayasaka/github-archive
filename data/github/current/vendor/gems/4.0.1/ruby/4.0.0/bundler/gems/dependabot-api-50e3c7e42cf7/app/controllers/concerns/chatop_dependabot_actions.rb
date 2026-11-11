# frozen_string_literal: true

module ChatopDependabotActions
  extend ActiveSupport::Concern

  included do
    chatop :repo_set_self_hosted,
           /repo[-_\s]set[-_\s]self[-_\s]hosted\s+(?<repo_ids>.+)/,
           "repo set self hosted REPO_IDS" \
           "- Sets the self-hosted on the specified repositories." do
      repo_ids = jsonrpc_params[:repo_ids].split(",")
      errors = []

      repo_ids.each do |repo_id|
        repo = Repo.find_by(id: repo_id.strip)
        if repo
          Dependabot::Application.dependabot_repository_settings_client.set_self_hosted_flag_on_repository(repo)
        else
          errors << "Repository with ID `#{repo_id}` not found."
        end
      end

      if errors.any?
        jsonrpc_error errors.join(", "), :not_found, errors.join(", ")
      else
        jsonrpc_success "Successfully enabled self-hosted for repositories: `#{repo_ids.join(', ')}`"
      end
    end
  end
end
