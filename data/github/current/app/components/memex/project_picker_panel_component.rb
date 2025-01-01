# typed: true
# frozen_string_literal: true

module Memex
  class ProjectPickerPanelComponent < ApplicationComponent
    attr_reader :team, :context, :viewer, :owner, :suggestions_path, :suggestions_recent_path, :singular_label, :plural_label, :multiselect

    alias multiselect? multiselect

    def initialize(team: nil, context:, viewer:, owner:, suggestions_path:, suggestions_recent_path:, is_template: false, multiselect: true)
      @team = team
      @context = context
      @viewer = viewer
      @owner = owner
      @suggestions_path = suggestions_path
      @suggestions_recent_path = suggestions_recent_path
      @is_template = is_template
      @singular_label = @is_template ? "template" : "project"
      @plural_label = @is_template ? "templates" : "projects"
      @multiselect = multiselect
      @select_panel = Primer::Alpha::SelectPanel.new(
        use_experimental_non_local_form: @experimental_non_local_feature_flag || false,
        id: "projects-select-menu",
        title: "Link #{@plural_label}",
        select_variant: multiselect? ? :multiple : :single,
        src: @suggestions_path,
        no_results_label: "No #{plural_label} found",
        size: :medium_portrait,
        data: {
          target: "memex-project-picker-panel.selectPanel"
        }
      )
    end

    delegate :with_show_button, :with_footer, to: :@select_panel

    private

    def before_render
      @experimental_non_local_feature_flag = user_feature_enabled?(:primer_select_panel_use_experimental_non_local_form)
      content
    end

    memoize def description_text
      if @context == Repository
        if @owner.organization?
          "Link a #{singular_label} from the organization to this repository"
        elsif @owner.is_a?(User)
          "Link a #{singular_label} to this repository"
        end
      elsif @context == Team
        "Link a #{singular_label} from the organization to this team"
      end
    end
  end
end
