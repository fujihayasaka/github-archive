# typed: true
# frozen_string_literal: true

class ProgrammaticAccess::PreviewMarkdownComponent < ApplicationComponent
  FORM_CLASSES = %w[form-control js-comment-field js-paste-markdown js-size-to-fit input-with-fullscreen-icon]

  def initialize(data_preview_url:, field:, name:, text_content: nil, **attributes)
    @data_preview_url = data_preview_url
    @field            = field
    @name             = name
    @text_content     = text_content

    @maxlength   = attributes[:maxlength]
    @placeholder = attributes.fetch(:placeholder, "")
    @short       = attributes.fetch(:short, false)
  end

  def form_options
    classes = FORM_CLASSES.dup

    options = {}.tap do |opts|
      opts[:id] = @name

      opts[:placeholder] = @placeholder
      opts["aria-label"] = @placeholder

      classes << "short width-full" if @short

      if @maxlength
        classes << "js-length-limited-input"
        opts[:maxlength] = @maxlength
        opts["data-input-max-length"] = @maxlength
        opts["data-warning-text"] = "{{remaining}} remaining"
      end

      opts[:class] = class_names(classes)
    end
  end

  def writing_on_github_docs_url
    "#{GitHub.help_url}/github/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax"
  end
end
