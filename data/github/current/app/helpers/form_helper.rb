# typed: true
# frozen_string_literal: true

# Special form helpers that generate a label/field combo from within a
# form_for block. For the most part, these work the same as default Rails
# form builder helpers, except they accept a text string (for the label) as the
# first parameter.
#
# These helpers make a few assumptions about how UX should work specific to
# GitHub (for example, we hide the hint when an error is present).
#
# The following helpers are supported:
#
# text_group      - <input type="text">
# password_group  - <input type="password">
# text_area_group - <textarea>
# select_group    - <select>
#
# Each helper accepts the following parameters:
#
# label   - String of used for the <label> element.
# field   - Symbol of the field name.
# options - Hash of options (optional).
#           :hint - String used for a field hint. Or...
#           :hint - Hash of options for the field hint. E.g. { text: "hint", class: "ignored"}
#           :group_class - A CSS class applied to <dl.form> element.
#           :required - Boolean to mark a field required.
#           :error - String of an error to display inline.
#           :field - Hash of options _only_ passed to the <input> element.
#
# Examples
#
#   <%= f.text_group "First Name", :name %>
#   <%= f.password_group "Password", :password, :hint => "Must be at least 500 chars" %>
#   <%= f.password_group "Password", :password, :hint => "Must be at least 500 chars" %>
#
# Returns a String of HTML including a label & field.
module FormHelper
  include ::TurboFormHelper
  class FieldData
    attr_accessor :field, :label, :description_id

    def initialize(label, field, description_id = nil)
      @field = field
      @label = label
      @description_id = description_id
    end
  end

  def field_wrap(label = nil, field = nil, options = {})
    if label.is_a?(Hash)
      options = label
      label = field = nil
    end

    class_name = "form-group #{options.delete(:group_class)}".dup
    class_name.strip!

    error = options.delete(:error)
    class_name << " errored" if error

    required = options[:required]
    class_name << " required" if required

    description_id = "description_#{SecureRandom.hex(6)}"

    h = options.delete(:hint)
    hint_opts = { class: "note", id: description_id }
    if h.is_a?(Hash)
      hint_text = h[:text]
      hint_opts[:class] += " #{h[:class]}"
    else
      hint_text = h
    end

    if h && !error
      hint = @template.content_tag(:p, hint_text, hint_opts)
      data = FieldData.new(label, field, description_id)
    else
      data = FieldData.new(label, field)
    end

    yield data if block_given?

    contents = @template.content_tag(:dt, data.label, class: "input-label")
    contents += @template.content_tag(:dd, data.field + hint.to_s)
    contents += @template.content_tag(:dd, error, class: "error", id: description_id) if error

    @template.content_tag(:dl, contents, class: class_name)
  end

  def text_group(text, method, options = {})
    options = options.merge(object: @object)
    field_only = options.delete(:field) || {}

    field_wrap(options) do |data|
      data.label = @template.label(@object_name, method, text, options.except(:value, :class))
      data.field = @template.text_field(@object_name, method, options.reverse_merge(field_only.merge("aria-describedby": data.description_id)))
    end
  end

  def password_group(text, method, options = {})
    options = options.merge(object: @object)
    @template.auto_check_tag(:password) do
      field_wrap(options) do |data|
        data.label = @template.label(@object_name, method, text, options.except(:value, :class))
        data.field = @template.password_field(@object_name, method, options.reverse_merge("aria-describedby": data.description_id))
      end
    end
  end

  def text_area_group(text, method, options = {})
    options = options.merge(object: @object)
    field_wrap(options) do |data|
      # label method destructively fetches options[:object]
      data.label = @template.label(@object_name, method, text, options.dup)
      data.field = @template.text_area(@object_name, method, options.reverse_merge("aria-describedby": data.description_id))
    end
  end

  def select_group(text, method, choices, options = {}, html_options = {})
    options = options.merge(object: @object)
    field_wrap(html_options) do |data|
      # label method destructively fetches options[:object]
      data.label = @template.label(@object_name, method, text, options.dup)
      data.field = @template.select(@object_name, method, choices, options, html_options.reverse_merge("aria-describedby": data.description_id))
    end
  end

  # Add some security to our form tags.
  #
  # Returns an HTML String.
  def form_tag_html(options = {})
    # Ensure that we aren't caching CSRF tokens.
    form_method(options) != "get" && GitHub::CacheLeakDetector.no_caching!

    super(options)
  end

  # Add some security to our button_to form tags.
  #
  # Returns an HTML String.
  def button_to(name, options = {}, html_options = {})
    # Ensure that we aren't caching CSRF tokens.
    GitHub::CacheLeakDetector.no_caching!

    html_options = html_options.stringify_keys
    html_options["form_class"] = "#{html_options["form_class"]}".strip

    super(name, options, html_options)
  end

  # Add default class to text_field
  #
  # returns text field form
  def text_field(object_name, method, options = {})
    super(object_name, method, merge_html_options_class(options, "form-control"))
  end

  def text_field_tag(name, value = nil, options = {})
    super(name, value, merge_html_options_class(options, "form-control"))
  end

  # Add default form-control class to password_field
  #
  # returns password_field
  def password_field(object_name, method, options = {})
    super(object_name, method, merge_html_options_class(options, "form-control"))
  end

  def password_field_tag(name, value = nil, options = {})
    super(name, value, merge_html_options_class(options, "form-control"))
  end

  # Add default class to text_area
  #
  # returns text area form
  def textarea(object_name, method, options = {})
    super(object_name, method, merge_html_options_class(options, "form-control"))
  end

  alias_method :text_area, :textarea

  def textarea_tag(name, content = nil, options = {})
    super(name, content, merge_html_options_class(options, "form-control"))
  end

  alias_method :text_area_tag, :textarea_tag

  # Add default class to select elements
  #
  # returns select form tag
  def select(object_name, method, choices, options = {}, html_options = {})
    super(object_name, method, choices, options, merge_html_options_class(html_options, "form-select"))
  end

  def select_tag(name, option_tags = nil, options = {})
    super(name, option_tags, merge_html_options_class(options, "form-select"))
  end

  # Add default class to select_tag
  #
  # returns text area form
  # def select(method, choices, options = {}, html_options = {})
  # super(method, choices, options, html_options.merge(:class => "form-control"))
  # end

  private

  def merge_html_options_class(options, class_name)
    options = options.symbolize_keys
    options[:class] = [class_name, options[:class]].compact.join(" ")
    options
  end

  def form_method(options)
    (options[:method] || options["method"] || "post").to_s.downcase
  end
end

ActionView::Base.default_form_builder.send :include, FormHelper
