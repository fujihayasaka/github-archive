# typed: true
# frozen_string_literal: true

class Api::MonaLisaOctocat < Api::App

  get "/octocat", operation_id: "meta/get-octocat" do
    control_access :apps_audited,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    content_type(user_agent.browser? ? "text/plain" : GitHub::OCTOCAT_CONTENT_TYPE)
    if params[:s] =~ /\A[\w\- ,\/]*\z/
      GitHub.octocat(params[:s])
    else
      GitHub.octocat
    end
  end

  get "/zen", operation_id: "meta/get-zen" do
    control_access :apps_audited,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    content_type "text/plain"
    GitHub.random_zen
  end
end
