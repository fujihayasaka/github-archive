# typed: strict
# frozen_string_literal: true

module SlashCommands
  SLASH_COMMAND_CONFIG = T.let(
    YAML.safe_load(Rails.root.join("config/slash_commands.yml").read),
    T::Hash[T.untyped, T.untyped]
  )

  UnsupportedSubjectType = Class.new(StandardError)

  DEFAULT_CATEGORY = :default

  # The "all" surface is a special surface used in snippet commands. It allows us to make the "surfaces" field
  # required while providing a convenient shorthand for command authors.
  ALL_SURFACE = "all"

  PULL_REQUEST_SURFACE = :pull_request
  PULL_REQUEST_BODY_SURFACE = :pull_request_body
  PULL_REQUEST_COMMENT_SURFACE = :pull_request_comment
  ISSUE_BODY_SURFACE = :issue_body
  ISSUE_SURFACE = :issue
  ISSUE_COMMENT_SURFACE = :issue_comment
  DISCUSSION_SURFACE = :discussion

  # The list of subject types we support webhook events for
  WEBHOOK_SUBJECT_TYPES = T.let([
    "IssueComment",
  ], T::Array[String])

  # This is the list of all supported surfaces.
  SUPPORTED_SURFACES = T.let([
    :discussion,
    :pull_request,
    :pull_request_body,
    :pull_request_comment,
    :issue,
    :issue_body,
    :issue_comment,
  ], T::Array[Symbol])

  # This is the hierarchy of supported surfaces.
  SURFACES = T.let({
    discussion: [],
    pull_request: [:pull_request_body, :pull_request_comment],
    issue: [:issue_body, :issue_comment],
  }, T::Hash[Symbol, T::Array[Symbol]])

  # Loads slash command classes, as specified by config.
  sig { returns(T::Array[T.class_of(SlashCommands::ApplicationSlashCommand)]) }
  def self.slash_command_classes
    @slash_command_classes ||= T.let(SLASH_COMMAND_CONFIG["slash_commands"].map(&:constantize), T.nilable(T::Array[T.class_of(SlashCommands::ApplicationSlashCommand)]))
  end

  sig { returns(T::Hash[String, T.class_of(SlashCommands::ApplicationSlashCommand)]) }
  def self.slash_command_classes_by_id
    @slash_command_classes_by_id ||= T.let(slash_command_classes.to_h do |command|
      [command.id, command]
    end, T.nilable(T::Hash[String, T.class_of(SlashCommands::ApplicationSlashCommand)]))
  end

  # Takes a slash command identifier and returns an instance of the related slash command class.
  # Returns a ApplicationSlashCommand subclass, or nil.
  sig { params(context: SlashCommands::Context, command_id: String, trigger_name: String).returns(T.nilable(SlashCommands::ApplicationSlashCommand)) }
  def self.find_command(context, command_id:, trigger_name:)
    return unless context.slash_commands_enabled?

    command = slash_command_classes_by_id[command_id]
    return unless command&.enabled?(context)

    context.trigger = command.triggers(context).detect { |trigger| trigger.name == trigger_name }
    return unless context.trigger.present?

    command.new(context)
  end

  sig { params(context: SlashCommands::Context).returns(T::Array[T.class_of(SlashCommands::ApplicationSlashCommand)]) }
  def self.all_commands(context)
    return [] unless context.slash_commands_enabled?

    slash_command_classes.select { |command| command.enabled?(context) }
  end

  sig { params(context: SlashCommands::Context, block: T.proc.params(trigger: SlashCommands::Trigger, command_class: T.class_of(SlashCommands::ApplicationSlashCommand)).void).void }
  def self.each_trigger(context, &block)
    all_commands(context).each do |command_class|
      command_class.triggers(context).each do |trigger|
        yield trigger, command_class if trigger.valid?
      end
    end
  end

  sig { params(surfaces: T::Array[T.any(String, Symbol)]).returns(T::Array[Symbol]) }
  def self.expand_surfaces(surfaces)
    expanded_surfaces = []
    surfaces.map(&:to_sym).each do |surface|
      expanded_surfaces.push(surface)
      (SlashCommands::SURFACES[surface] || []).each do |child_surface|
        expanded_surfaces.push(child_surface)
      end
    end

    expanded_surfaces.compact.uniq
  end

  sig { params(surface: T.any(NilClass, String, Symbol)).returns(T::Boolean) }
  def self.supported_surface?(surface)
    return false if surface.blank?

    SUPPORTED_SURFACES.include?(surface.to_sym)
  end

  # Takes an instance or a class as it's subject.
  # Returns a surface symbol, if the surface is supported.
  # Otherwise returns nil.
  sig { params(subject: T.any(NilClass, String, Object)).returns(T.nilable(Symbol)) }
  def self.surface_for(subject)
    return nil if subject.nil?

    if subject.is_a?(String)
      begin
        GitHub.dogstats.increment("slash_commands.surface_for", tags: ["case:string"])
        subject = subject.constantize
      rescue NameError => e
        Failbot.report(e, provided_subject: subject)
        GitHub.dogstats.increment("slash_commands.surface_for", tags: ["case:string_error"])
        subject = nil
      end
    end

    klass = if subject.is_a?(Class)
      GitHub.dogstats.increment("slash_commands.surface_for", tags: ["case:class"])
      subject
    else
      GitHub.dogstats.increment("slash_commands.surface_for", tags: ["case:class_instace"])
      subject.class
    end

    # Handle PlatformTypes
    if klass.respond_to?(:type) && klass.type.respond_to?(:model_name)
      GitHub.dogstats.increment("slash_commands.surface_for", tags: ["case:platform_type"])
      klass = klass.type.model_name.constantize
    end

    surface = klass.name.underscore.to_sym

    return nil unless supported_surface?(surface)
    surface
  end

  sig { params(user: T.nilable(User), repository: T.any(NilClass, Repository, Issue::Adapter::RepositoryAdapter, T::Hash[T.untyped, T.untyped])).returns(T::Boolean) }
  def self.enabled_for?(user, repository)
    return false unless user.present?

    # Ensure the feature is enabled
    result = user.slash_commands_enabled?

    if repository
      result ||= repository.is_a?(Hash) ? repository[:slash_commands_enabled?] : repository.slash_commands_enabled?
    end

    result
  end

  sig { params(subject: T.untyped).returns(T.nilable(String)) }
  def self.subject_gid(subject)
    return nil unless subject.present?
    # This filters out non-ActiveRecord subjects
    return nil unless subject.respond_to?(:new_record?)
    # This filters out records which havent been saved yet
    return nil if subject.new_record?
    return nil unless subject.respond_to?(:global_relay_id)

    subject.global_relay_id
  end

  sig { params(repo_owner_login: String, repo_name: String, subject_gid: T.nilable(String), surface: T.any(NilClass, Symbol, String)).returns(String) }
  def self.expander_url(repo_owner_login:, repo_name:, subject_gid:, surface: nil)
    path_params = {
      user_id: repo_owner_login,
      repository: repo_name,
      subject_gid: subject_gid,
      surface: surface,
    }

    Rails.application.routes.url_helpers.slash_apps_path(path_params)
  end

  sig { params(adapter_instance: T.untyped).returns(T.nilable(Symbol)) }
  def self.surface_for_issue_adapter(adapter_instance)
    return PULL_REQUEST_SURFACE if adapter_instance.is_a?(PlatformTypes::IssueComment) && adapter_instance.pull_request
    return ISSUE_COMMENT_SURFACE if adapter_instance.is_a?(PlatformTypes::IssueComment)
    return PULL_REQUEST_SURFACE if adapter_instance.is_a?(PlatformTypes::PullRequest)
    ISSUE_BODY_SURFACE if adapter_instance.is_a?(PlatformTypes::Issue)
  end

  sig { params(text: String).returns(T::Boolean) }
  def self.may_contain_commands?(text)
    text.match?(/^\/(.*)/)
  end

  sig { params(text: String).returns(T::Array[String]) }
  def self.extract_embedded_commands(text)
    text.scan(/^\/(.*)/).flatten.map(&:strip)
  end

  sig { params(subject: IssueComment).returns(T::Boolean) }
  def self.embedded_commands_candidate?(subject)
    repository = subject.repository

    return false if repository.nil?
    self.embedded_commands_repository?(repository)
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.embedded_commands_repository?(repository)
    owned_by = repository.owner
    !!(owned_by.present? && owned_by.organization? && GitHub.flipper[:embedded_slash_commands].enabled?(owned_by))
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.snippets_repository?(repository)
    return false if repository.public?

    owned_by = repository.owner
    !!(owned_by.present? && owned_by.organization? && GitHub.flipper[:snippet_slash_commands].enabled?(owned_by))
  end
end
