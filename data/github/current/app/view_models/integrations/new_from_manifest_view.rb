# typed: true
# frozen_string_literal: true

class Integrations::NewFromManifestView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :integration, :manifest, :owner, :manifest_token, :state

  def page_title
    "Create GitHub App"
  end

  def selected_link
    :integrations
  end

  def owner_name
    owner.display_login
  end
end
