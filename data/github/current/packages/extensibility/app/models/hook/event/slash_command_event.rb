# typed: true
# frozen_string_literal: true

class Hook::Event::SlashCommandEvent < Hook::Event
  supports_targets Organization

  feature_flag :embedded_slash_commands

  description "A slash command was posted to an issue comment."

  event_attr :command, required: true
  event_attr :subject_type, required: true
  event_attr :subject_id, required: true

  def action
    :slash_command_posted
  end

  def target
    raise SlashCommands::UnsupportedSubjectType unless supported_subject_type?
    @target ||= subject_type.constantize.find_by_id(subject_id)
  end

  def target_repository
    target.repository
  end

  def actor
    if target.is_a?(IssueComment)
      target.user
    end
  end

  def deliverable?
    supported_subject_type? && actor.present? && target_organization.present?
  end

  private

  def supported_subject_type?
    SlashCommands::WEBHOOK_SUBJECT_TYPES.include?(subject_type)
  end
end
