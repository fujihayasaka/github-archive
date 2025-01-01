# typed: true
# frozen_string_literal: true

class Memex::ProjectList::CopyProjectDialogComponent < ApplicationComponent
  delegate :avatar_for, to: :helpers

  def initialize(project:, copy_as_template: false)
    @project = project
    @copy_as_template = copy_as_template
  end

  def dialog_text
    @copy_as_template ? "Copy as template" : "Make a copy"
  end

  def dialog_id
    @copy_as_template ? "copy-as-template-dialog-#{@project.number}" : "copy-project-dialog-#{@project.number}"
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

  def description_for_copy_dialog
    if @copy_as_template
      "Copy this project into a template that can be used when creating new projects."
    else
      "Make a copy of this project that can be used as a starting point for another project."
    end
  end
end
