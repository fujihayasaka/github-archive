# typed: strict
# frozen_string_literal: true

module SlashCommands
  class Trigger
    extend T::Sig

    COMPOSITE_ID_SEPARATOR = ";"

    sig { returns(String) }
    attr_reader :name

    sig { returns(String) }
    attr_reader :title

    sig { returns(T.nilable(String)) }
    attr_reader :description

    sig { returns(T.class_of(ApplicationSlashCommand)) }
    attr_reader :command

    sig { returns(T.nilable(String)) }
    attr_reader :value

    sig { returns(T.nilable(Repository)) }
    attr_reader :command_source_repository

    sig { returns(T.nilable(String)) }
    attr_accessor :url

    delegate :id, to: :command

    sig { params(command: T.class_of(ApplicationSlashCommand), name: String, title: String, url: T.nilable(String), description: T.nilable(String), value: T.nilable(String), command_source_repository: T.nilable(Repository)).void }
    def initialize(command:, name:, title:, url: nil, description: nil, value: nil, command_source_repository: nil)
      @command = command
      @name = name
      @url = url
      @title = title
      @description = description
      @value = value
      @command_source_repository = command_source_repository
    end

    sig { returns(T::Boolean) }
    def description?
      !!description
    end

    sig { returns(String) }
    def composite_id
      id + COMPOSITE_ID_SEPARATOR + name
    end

    sig { returns(Symbol) }
    def category
      command._category
    end

    sig { returns(T::Boolean) }
    def valid?
      title.present? && name.present?
    end
  end
end
