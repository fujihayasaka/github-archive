# typed: true
# frozen_string_literal: true

class Codespaces::PrebuildConfigurations::AdvancedOptionsComponent < ApplicationComponent
  def initialize(form:, repo:, fast_path_enabled:)
    @form = form
    @repo = repo
    @fast_path_enabled = fast_path_enabled
  end

  def show_advanced_options_msg
    "Show advanced options"
  end

  def hide_advanced_options_msg
    "Hide advanced options"
  end

  def disable_optimization_msg
    "You can disable prebuild optimization if you're having issues where codespaces are several commits behind on a specific branch."
  end

  def disable_optimization_msg_note
    "This prevents codespaces from attempting to use an older image to speed up boot time. This could adversely affect performance."
  end

  private

  attr_reader :form, :repo, :fast_path_enabled
end
