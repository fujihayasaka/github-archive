# typed: true
# frozen_string_literal: true

class Codespaces::UseTemplateDropdownComponent < ApplicationComponent
  include HydroHelper

  attr_reader :repository
  attr_reader :clone_url

  renders_one :form_content

  def initialize(repository:, clone_url:)
    @repository = repository
    @clone_url = clone_url
  end

  def template
    Codespaces::Template.for_repository(@repository)
  end

  def click_tracking_attributes
    payload = {
      ref: template.repository.default_branch,
      repository_id: template.repository.id,
      target: "USE_TEMPLATE_DROPDOWN",
      user_id: current_user.id
    }
    hydro_click_tracking_attributes("codespace_create.click", payload)
  end
end
