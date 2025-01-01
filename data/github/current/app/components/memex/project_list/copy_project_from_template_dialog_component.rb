# typed: true
# frozen_string_literal: true

class Memex::ProjectList::CopyProjectFromTemplateDialogComponent < ApplicationComponent
  delegate :avatar_for, to: :helpers

  def initialize(project:, template_id:, current_user:)
    @project = project
    @current_user = current_user
    @template_id = template_id
  end

  def dialog_text
    "Use this template"
  end

  def dialog_id
    "copy-from-template-dialog-#{@project.number}"
  end

  def owner
    @project.owner
  end

  def form_path
    params = { memex_number: @project.number, user_id: owner.display_login }

    if owner.user?
      copy_user_memex_path(params)
    else
      copy_org_memex_path(params.merge(org: owner))
    end
  end
end
