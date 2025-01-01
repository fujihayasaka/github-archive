# typed: true
# frozen_string_literal: true

module CommandPalette
  class ResultScope
    CLASS_TO_TYPE = {
      "User" => "owner",
      "Organization" => "owner",
      "Repository" => "repository",
      "Issue" => "issue",
      "Discussion" => "discussion",
      "PullRequest" => "pull_request",
      "MemexProject" => "memex_project",
    }

    attr_reader :tokens

    def initialize(object)
      @object = object
      @class = @object.class.name
      @type = CLASS_TO_TYPE[@class]

      case @class
      when "User", "Organization"
        for_owner
      when "Repository"
        for_repository
      when "Issue", "Discussion", "PullRequest"
        for_repository_resource
      when "MemexProject"
        for_memex_project
      else
        raise ArgumentError, "expected class to be in #{CLASS_TO_TYPE.keys}, got #{@object.class}"
      end
    end

    def as_json(*)
      {
        tokens: tokens
      }
    end

    private

    def for_owner
      @tokens = [CommandPalette::ResultToken.new(id: @object.global_relay_id, type: @type, text: @object.display_login)]
    end

    def for_memex_project
      @tokens = [
        CommandPalette::ResultToken.new(id: @object.owner.global_relay_id, type: "owner", text: @object.owner.display_login),
        CommandPalette::ResultToken.new(id: @object.global_relay_id, type: @type, text: "Project ##{@object.number}")
      ]
    end

    def for_repository
      @tokens = [
        CommandPalette::ResultToken.new(id: @object.owner.global_relay_id, type: "owner", text: @object.owner.display_login),
        CommandPalette::ResultToken.new(id: @object.global_relay_id, type: @type, text: "#{@object.name}", value: @object.name)
      ]
    end

    def for_repository_resource
      @tokens = [
        CommandPalette::ResultToken.new(id: @object.repository.owner.global_relay_id, type: "owner", text: @object.repository.owner.display_login),
        CommandPalette::ResultToken.new(id: @object.repository.global_relay_id, type: "repository", text: "#{@object.repository.name}"),
        CommandPalette::ResultToken.new(id: @object.global_relay_id, type: @type, text: "#{@object.class.name.underscore.humanize.pluralize} ##{@object.number}")
      ]
    end
  end
end
