# typed: true
# frozen_string_literal: true

class Codespaces::Forms::BranchSelectComponent < ApplicationComponent

  def initialize(
    repository:,
    form: nil,
    initial_branch_ref: nil,
    default_branch: nil,
    cache_key:,
    autosubmit: false,
    form_field: :branch,
    button_option_overrides: {},
    right_aligned: false
  )
    @repository = repository
    @default_branch = default_branch || repository.default_branch
    @branch = initial_branch_ref&.name_for_display || ""
    @selected_branch = @branch.present? ? @branch : "Select branch"
    @form = form
    @form_field = form_field
    @cache_key = cache_key
    @autosubmit = autosubmit
    @button_option_overrides = button_option_overrides
    @right_aligned = right_aligned
  end

  def button_options
    { tag: :summary, variant: :small, display: :flex, justify_content: :space_between }.merge(button_option_overrides)
  end

  private

  attr_reader :repository, :form, :branch, :cache_key, :autosubmit, :form_field, :button_option_overrides, :default_branch, :selected_branch, :right_aligned
end
