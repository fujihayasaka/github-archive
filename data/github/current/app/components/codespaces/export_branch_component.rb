# typed: true
# frozen_string_literal: true

class Codespaces::ExportBranchComponent < ApplicationComponent
  renders_one :generate_branch_button
  renders_one :loading_indicator
  renders_one :view_branch_button

  attr_reader :codespace, :needs_fork

  def initialize(codespace:, needs_fork: false)
    @codespace = codespace
    @needs_fork = needs_fork
  end

  def export_target
    if @needs_fork && !@codespace.owner.repositories.find_by_parent_id(@codespace.repository_id)
      # Only render this if using a *new* fork.
      "fork"
    elsif @codespace.unpublished? || (@codespace.template_repository_id && @codespace.repository.empty?)
      "repository"
    else
      "branch"
    end
  end

  def export_target_link
    if @codespace.unpublished? || needs_fork
      published_codespace_path(codespace)
    else
      tree_path("", codespace.export_branch_name, codespace.repository)
    end
  end

  def export_status
    if @codespace.fresh_export_exists?
      :exported # View branch state
    elsif @codespace.exporting? && !@codespace.stuck_exporting?
      :exporting # Spinner state
    else
      :exportable # Initial state
    end
  end
end
