# typed: false
# frozen_string_literal: true

module CommunityHelper
  def community_generator_form_path(filename, branch)
    if current_repository.includes_file?(filename, branch)
      file_edit_path(current_repository.owner, current_repository, branch, filename)
    else
      new_file_path(current_repository.owner, current_repository, branch)
    end
  end

  # Given a License or Code of Conduct, returns the rendered/safe HTML
  # representation of the template for the template/coc picker, including
  # the necessary `<span>`s to support the picker's dynamic field filling
  #
  # See https://git.io/fADRQ for more information on HTML sanitization
  #
  # Returns the .html_safe string for use in the template picker
  def rendered_community_template(template)
    tag_class = "CommunityTemplate-highlight js-template-highlight"

    result = GitHub::Goomba::MarkdownPipeline.call(template.content, {})
    output = result[:output]
    output = output.gsub("<br>\n", GitHub::HTMLSafeString::NBSP)

    template.fields.each do |field|
      replacement = content_tag(:span, field.label, class: tag_class, data: { fieldname: field.key })
      output = output.gsub(field.raw_text, replacement)
    end

    result[:html_safe] ? output.html_safe : output # rubocop:disable Rails/OutputSafety
  end
end
