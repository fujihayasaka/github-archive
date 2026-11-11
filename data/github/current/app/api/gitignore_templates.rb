# typed: strict
# frozen_string_literal: true

class Api::GitignoreTemplates < Api::App
  get "/gitignore/templates", operation_id: "gitignore/get-all-templates" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    deliver_raw(Gitignore.templates, status: 200)
  end

  get "/gitignore/templates/:key", operation_id: "gitignore/get-template" do
    control_access :public_site_information, resource: Platform::PublicResource.new, allow_integrations: true, allow_user_via_granular_actor: true # rubocop:disable GitHub/PublicResource

    name = params[:key]
    template = Gitignore.template(name)
    deliver_error!(404, documentation_url: "/v3/gitignore") unless template.present?

    if medias.api_param?(:raw)
      deliver_raw template, content_type: "#{medias}; charset=utf-8"
    else
      deliver_raw(name: name, source: template)
    end
  end
end
