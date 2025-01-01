# typed: true
# frozen_string_literal: true

class SlashCommands::StepBuilder::Flash < SlashCommands::StepBuilder::Fill
  def page
    SlashCommands::Page.new(type: :action) do |command|
      markdown = render(command)
      command.flash.notice = markdown_to_html(markdown, command)
    end
  end

  def markdown_to_html(markdown, command)
    context = {
      entity: command.current_repository,
      current_user: command.current_user
    }

    # TODO: Make it so we don't have to strip the wrapping <p>.
    html = GitHub::Goomba::MarkdownPipeline.to_html(markdown, context, nil)
    html_without_p_tag = html.gsub(/\A<p.*?>|<\/p>\z/, "")
    ActiveSupport::SafeBuffer.new(html_without_p_tag)
  end
end
