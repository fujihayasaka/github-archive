# typed: true
# frozen_string_literal: true

module SlashCommands
  class Context
    class InvalidError < StandardError; end

    attr_reader :current_repository, :subject_gid, :subject_id, :subject_type, :current_user, :data, :surface
    attr_accessor :trigger

    def initialize(current_repository:, subject_gid: nil, current_user:, surface: nil, data: nil, page_number: nil)
      @current_repository = current_repository
      @current_user = current_user
      @data = data || {}
      @page_number = page_number || 1
      @subject_gid = subject_gid

      raise ArgumentError, "A subject_gid or surface is required." unless subject_gid.present? || surface.present?

      if subject_gid.present?
        @subject_type, @subject_id = Platform::Helpers::NodeIdentification.from_global_id(subject_gid)
      else
        @subject_type = nil
        @subject_id = nil
      end

      if surface.present?
        @surface = surface&.to_sym
      elsif @subject_type.present?
        @surface = SlashCommands.surface_for(@subject_type)
      end

      raise InvalidError, "Requires a valid subject or a surface." unless SlashCommands.supported_surface?(@surface)
    end

    def slash_commands_enabled?
      current_user.slash_commands_enabled? || current_repository.slash_commands_enabled?
    end

    # Returns a resouce if one exists
    def subject
      return nil unless current_repository.present?
      return nil unless subject_type.present?
      return nil unless subject_id.present?

      return @subject if defined?(@subject)

      @subject = begin
        case subject_type
        when "Discussion" then current_repository.discussions.find_by(id: subject_id)
        when "Issue" then current_repository.issues.find_by(id: subject_id)
        when "PullRequest" then current_repository.pull_requests.find_by(id: subject_id)
        else
          nil
        end
      end
    end

    def previous_page!
      return unless page_number
      @page_number = page_number - 1
    end

    def next_page!
      return unless page_number
      @page_number = page_number + 1
    end

    def page_number
      Integer(@page_number)
    rescue ArgumentError, TypeError
      nil # When value provided is malformed, ignore it
    end

    def issue
      return nil if subject.nil?

      if subject.is_a?(PullRequest)
        subject.issue
      elsif subject.is_a?(Issue)
        subject
      else
        nil
      end
    end
  end
end
