# typed: true
# frozen_string_literal: true

module CommandPalette
  class Result
    extend UrlHelpers
    extend ConditionalAccessHelper

    # Adds or subtracts from the given priority
    PRIORITY_WEIGHTS = {
      current_user: 1, # small weight to get your user higher than other users
      org_default: 5, # orgs should always get at least this to be higher than users
      # below are weights for affiliated orgs
      outside_collaborator: 6,
      billing_manager: 6,
      member: 7,
      admin: 8,
    }

    # Builds result that links to a user, repository, project, memex project, or team
    def self.jump_to(object, priority: 1, context:, group: nil)
      case object
      when *Results::Factory::RESULT_TYPES.keys
        Results::Factory.build(object, priority, context, group)
      else
        Failbot.report(ArgumentError.new("expected #{Results::Factory::RESULT_TYPES.values}, but got #{object.class}"))
      end
    end

    # Build result that links to a page
    def self.link_to(title:, icon:, path:, priority: CommandPalette::PageNavigator::DEFAULT_PRIORITY, match_fields: nil, group: :pages, object: nil)
      new(
        priority: priority,
        title: title,
        icon: Icons::Octicon.new(name: icon),
        match_fields: match_fields,
        action: Actions::JumpToAction.new(path: path),
        group: group,
        object: object
      )
    end

    def self.access_policy(policy, target, return_to)
      path_or_nil = restricted_raw_path(policy, target, return_to)
      path = path_or_nil.nil? ? "" : path_or_nil

      joiner, type = if target.is_a?(Business)
        %w[the enterprise]
      elsif target.is_a?(Organization)
        %w[the organization]
      else
        ["", ""]
      end

      names = []

      if target.respond_to?(:name) && target.name.present?
        names << target.name
      elsif target.respond_to?(:login) && target.login.present?
        names << target.login
      end

      new(
        title: "#{policy_satisfy_criteria_label(policy)} to see results within #{joiner} #{names.first} #{type}",
        priority: 100,
        typeahead: names.first,
        icon: Icons::Octicon.new(name: "shield-lock"),
        match_fields: names,
        action: Actions::AccessPolicyAction.new(path: path),
        group: :access_policies
      )
    end

    # Allows the url helpers to work within class methods
    def self.url_options
      { host: GitHub.host_name }
    end

    # Allows the url helpers to work within class methods for #restricted_raw_path
    def self.default_url_options
      self.url_options
    end

    # Allows the url helpers to work within class methods for #restricted_raw_path
    def self.optimize_routes_generation?
      # from lib/action_dispatch/routing/route_set.rb
      default_url_options.empty?
    end

    attr_reader :title, :icon, :action, :subtitle, :scope, :priority
    attr_accessor :group, :match_fields, :typeahead, :hint, :object

    def initialize(title:, icon:, action:, subtitle: nil, typeahead: nil, scope: nil, priority: 0, group:, match_fields: nil, hint: nil, object: nil)
      validate_group(group)

      @title = title
      @subtitle = subtitle
      @scope = scope
      @typeahead = typeahead
      @icon = icon
      @priority = priority
      @action = action
      @group = group
      @match_fields = match_fields
      @hint = hint
      @object = object
    end

    def validate_group(group)
      groups = ResultGroups::REGISTERED_GROUPS
      raise ArgumentError, "group must be one of: #{groups.join(", ")} or added to ResultGroups::REGISTERED_GROUPS" unless groups.include?(group)
    end

    def as_json(*)
      {
        priority: priority,
        title: title,
        subtitle: subtitle,
        match_fields: match_fields,
        typeahead: typeahead,
        scope: scope,
        icon: icon,
        action: action,
        group: group,
        hint: hint,
      }.reject { |_key, value| value.nil? }
    end

    def ==(other)
      to_json == other.to_json
    end
  end
end
