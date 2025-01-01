# typed: false
# frozen_string_literal: true

module Refs
  class PickerComponent < ApplicationComponent
    renders_one :summary, -> (title, show_icon = true, prefix: nil, **system_arguments) do
      render Primer::ButtonComponent.new(tag: :summary, dropdown: true, **system_arguments) do |c| # rubocop:disable Primer/DeprecatedComponents
        c.with_leading_visual_icon(icon: :tag) if show_icon
        @content = (content_tag :i, prefix.present? ? prefix : "")
        @content << content_tag(:span, title, "data-menu-button": "")
      end
    end

    # Renders a picker to select different kinds of refs.
    # It works in 2 modes: navigate (items are anchors) or select (items have hidden radio inputs)
    # By providing option input_object_name, the component will render in select mode.
    # - tag_name: the selected tag
    # - repository: the current repository
    # - mode: :navigate or :selector so items are either anchors or radio inputs
    # - options:
    #   - header: the header of the popup
    #   - placeholder: the message in the search textbox when empty
    #   - autofocus: set keyboard focus on the picker when page loads
    #   - hide_footer: hides the view all link at the end of the popup
    #   - input_object_name: name of the object to generate an input for
    #   - input_field_name: name of the field to generate an input for
    #   - can_create: displays the "Create tag" line if no exact match. Default to false
    #   - details_classes: classes to add to details element, can be used to set direction for open by adding position-relative class
    #   - details_menu_classes: classes to add to detail-menu-element, can be used to right-align menu by seeting class right-0
    # TODO Currently, this picker only supports Tags. It will be extended for Branches and Latest commits
    def initialize(tag_name:, repository:, mode: :navigate, **options)
      @tag_name = tag_name
      @repository = repository
      @mode = mode
      @options = options

      @use_partial = options.delete(:use_partial)

      raise ArgumentError, "Missing input_object_name option parameter in selector mode" if selector? && input_object_name.blank?
      raise ArgumentError, "Missing input_field_name option parameter in selector mode" if selector? && input_field_name.blank?

      guid = SimpleUUID::UUID.new.to_guid
      @select_menu_id = "tag-select-menu-#{guid}"
    end

    private

    attr_reader :tag_name, :select_menu_id

    def use_partial?
      if @use_partial == true
        FeatureFlag.vexi.enabled?(:releases_update_ref_selector, current_user, default: false)
      else
        false
      end
    end

    def header
      @options[:header] || "Choose a tag to compare"
    end

    def placeholder
      @options[:placeholder] || "Find a tag"
    end

    def prefix
      @options[:prefix]
    end

    def button_text
      @options[:button_text]
    end

    def persist_button_text
      @options.fetch(:persist_button_text, true)
    end

    def aria_label
      # Calculate the complete aria-label based on button_text and prefix
      if button_text && persist_button_text
        text = button_text
      elsif @tag_name.present?
        text = @tag_name
      else
        text = button_text || ""
      end

      prefix.present? ? "#{prefix}: #{text}" : text
    end

    def id_ending
      @options[:id_ending] || "releases-ref-selector"
    end

    def show_icon
      @options.fetch(:show_icon, true)
    end

    def size
      @options[:size] || "medium"
    end

    def autofocus
      @options[:autofocus]
    end

    def hide_footer
      @options[:hide_footer]
    end

    def can_create?
      @options[:can_create]
    end

    def details_menu_classes
      @options[:details_menu_classes] || ""
    end

    def details_classes
      @options[:details_classes] || ""
    end

    def tags_query_url
      refs_ref_list_path(repository: @repository.name, user_id: @repository.owner_display_login)
    end

    def tag_url_template
      url = compare_path(@repository, "#{RefsHelper::PLACEHOLDER_STRING}...#{@tag_name}")
      # Rails will encode '{' and '}' characters, so we need to avoid curly braces in the generate path call
      url.sub(RefsHelper::PLACEHOLDER_STRING, "{{ urlEncodedRefName }}")
    end

    def selector?
      @mode == :selector
    end

    def input_object_name
      @options[:input_object_name]
    end

    def input_field_name
      @options[:input_field_name]
    end

    def all_tags_url
      tags_path(@repository.owner_display_login, @repository)
    end

    def ref_list_cache_key
      # Copied from BranchesHelper. How to better reuse this?
      "v0:#{@repository.refset_updated_at.to_f}"
    end

    def encoded_commitish
      Base64.strict_encode64(@tag_name.to_s)
    end

    def encoded_default_branch
      Base64.strict_encode64(@repository.default_branch)
    end

    def encoded_name_with_owner
      Base64.strict_encode64(@repository.name_with_display_owner)
    end
  end
end
