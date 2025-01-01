# typed: false
# frozen_string_literal: true

module SlashCommands
  class SlashCommandExpanderWrapperComponent < ApplicationComponent
    include SlashCommandsHelper

    # NOTE: Repository may not be an actual repository. It may be a hash in cases GraphQL is involved.
    # In that case, a hash with the following schema is expected:
    # {
    #   repo_name: ...,
    #   owner_login: ...,
    #   slash_commands_enabled?: ...
    # }
    attr_reader :repository, :user

    def self.with_url(repository:, user:, url:)
      new(repository: repository, user: user, url: url)
    end

    # repository – the current repository
    # user - the current user
    # subject - the subject of the text area (Issue/PR/Discussion). Can instead pass in subject_gid
    #           in it's place, or surface if a subject does not exist.
    # subject_gid - the subject's global id. Can instead pass in subject in it's place, or surface if a subject does not exist.
    # surface - a symbol representing a slash command surface. Only needed if a subject or subject_gid is nil.
    # url – the URL to get the list of slash commands. Provide this instead of surface and subject_gid.
    def initialize(
      repository:,
      user:,
      subject: nil,
      subject_gid: nil,
      surface: nil,
      url: nil
    )
      @repository = repository
      @user = user
      @subject = subject
      @subject_gid = subject_gid
      @surface = surface
      @url = url
    end

    def url
      return @url if @url.present?
      SlashCommands.expander_url(
        repo_owner_login: repo_owner_login,
        repo_name: repo_name,
        subject_gid: subject_gid,
        surface: surface
      )
    end

    memoize def subject_gid
      # If a GID is given, skip this logic
      return @subject_gid unless @subject_gid.nil?

      @subject_gid ||= SlashCommands.subject_gid(@subject)
    end

    def surface
      return @surface if @surface.present?
      return nil unless subject_gid.present?
      subject_type, _ = Platform::Helpers::NodeIdentification.from_global_id(subject_gid)
      SlashCommands.surface_for(subject_type)
    end

    memoize def repo_owner_login
      return nil if repository.nil?
      repository.is_a?(Hash) ? repository[:owner_login] : repository&.owner&.display_login
    end

    def repo_name
      return nil if repository.nil?
      repository.is_a?(Hash) ? repository[:name] : repository&.name
    end

    def enabled?
      return false unless slash_commands_enabled?

      # Exit early if a URL has already been generated
      return true if @url.present?

      # Must be a supported field
      return false unless SlashCommands.supported_surface?(surface)

      # Must have repo identifying fields
      return false unless repo_name.present? && repo_owner_login.present?

      true
    end

    def current_user
      user
    end

    def current_repository
      repository
    end
  end
end
