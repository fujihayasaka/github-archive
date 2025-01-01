# typed: true
# frozen_string_literal: true

class Codespaces::RefComponent < ApplicationComponent
  attr_reader :codespace

  def initialize(codespace:, should_truncate: false, show_tooltip: false, show_branch_icon: true, link_to_repo: true, extra_classes: "", disabled: false, dropdown: false)
    @codespace = codespace
    @should_truncate = should_truncate
    @show_tooltip = show_tooltip
    @show_branch_icon = show_branch_icon
    @link_to_repo = link_to_repo
    @disabled = disabled
    @dropdown = dropdown
    @extra_classes = extra_classes
  end

  def tooltip_text
    if codespace.has_uncommitted_changes? && detached_head?
      "Working directory is not clean and is in 'detached HEAD' state (#{display_ref_name})"
    elsif codespace.has_uncommitted_changes?
      "Working directory is not clean (#{display_ref_name})"
    elsif detached_head?
      "Working directory is in 'detached HEAD' state (#{display_ref_name})"
    end
  end

  def show_tooltip?
    @show_tooltip && tooltip_text
  end

  def branch_label_options
    {
      repository: codespace.repository,
      branch: display_ref_name,
      expandable: false,
      link: @link_to_repo,
      branch_octicon: @show_branch_icon,
      suffix: tooltip_text ? "*" : "",
      extra_classes: "Truncate #{@should_truncate ? 'css-truncate css-truncate-target' : ''} commit-ref mr-1 #{extra_classes}",
      octicon_classes: "#{detached_head? ? "color-fg-muted" : ""}",
      truncate_branch_only: true
    }
  end

  private

  def extra_classes
    @extra_classes + " " + if detached_head?
      "color-bg-subtle"
    elsif @disabled
      "color-bg-subtle color-fg-muted"
    elsif @dropdown
      "color-bg-accent color-fg-default"
    else
      "color-bg-accent color-fg-muted"
    end
  end

  def detached_head?
    !codespace.current_branch && codespace.current_commit
  end

  def display_ref_name
    detached_head? ? codespace.display_branch[0..Commit::ABBREVIATED_OID_LENGTH] : codespace.display_branch
  end
end
