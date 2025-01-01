# typed: false
# frozen_string_literal: true

module Repository::NetworkPrivilegeDependency
  extend ActiveSupport::Concern

  included do
    has_one :network_privilege, class_name: "Stafftools::NetworkPrivilege", dependent: :destroy
  end

  # Public: Is this repository prevented from being indexed by search engines?
  #
  # Returns a Promise<Boolean>.
  def async_noindex?
    async_network_privilege.then do |privilege|
      next false unless privilege
      privilege.noindex?
    end
  end

  # Public: Is this repository prevented from being indexed by search engines?
  #
  # Returns a Boolean.
  def noindex?
    async_noindex?.sync
  end

  def set_network_privilege(type, value, actor: nil)
    self.network_privilege ||= Stafftools::NetworkPrivilege.new
    self.network_privilege[type] = value
    self.network_privilege.save!

    if type == :no_index
      context = event_context.merge({ hide_from_google: network_privilege[type] })
    else
      context = event_context.merge({ type => network_privilege[type] })
    end

    if value == true
      GlobalInstrumenter.instrument "repository.visibility_downgraded", context.merge({ actor:, repository: self })
    end

    instrument type, context
  end

  # Public: Are users required to login to view this repository?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Promise<Boolean>.
  def async_require_login?
    async_network_privilege.then do |privilege|
      next false unless privilege
      privilege.require_login?
    end
  end

  # Public: Are users required to login to view this repository?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Boolean.
  def require_login?
    async_require_login?.sync
  end

  # Public: Are users required to opt-in to view this repository?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Promise<Boolean>.
  def async_require_opt_in?
    async_network_privilege.then do |privilege|
      next false unless privilege
      privilege.require_opt_in?
    end
  end

  # Public: Are users required to opt-in to view this repository?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Boolean.
  def require_opt_in?
    async_require_opt_in?.sync
  end

  # Public: Are only collaborators able to view this repository?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Promise<Boolean>.
  def async_collaborators_only?
    async_network_privilege.then do |privilege|
      next false unless privilege
      privilege.collaborators_only?
    end
  end

  # Public: Are only collaborators able to view this repository?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Boolean.
  def collaborators_only?
    async_collaborators_only?.sync
  end

  # Public: Is this repository hidden from the `/discover` and `/explore` pages?
  #
  # Returns a Promise<Boolean>.
  def async_is_hidden_from_discovery?
    async_network_privilege.then do |privilege|
      next false unless privilege
      privilege.hide_from_discovery?
    end
  end

  # Public: Is this repository hidden from the `/discover` and `/explore` pages?
  #
  # Returns a Boolean.
  def is_hidden_from_discovery?
    async_is_hidden_from_discovery?.sync
  end

  # Public: Should this repository render a content warning of the given type?
  #         Content warning types are: banner | interstitial
  #
  # Returns a Promise<Boolean>.
  def async_should_render_content_warning_for?(type)
    async_network_privilege.then do |privilege|
      next false unless privilege
      TrustSafety::ContentWarnings.type_for(privilege.content_warning_category) == type
    end
  end

  # Public: Should this repository render a content warning of the given type?
  #         Content warning types are: banner | interstitial
  #
  # Returns a Boolean.
  def should_render_content_warning_for?(type)
    async_should_render_content_warning_for?(type).sync
  end

  # Public: Does this repository have a content warning?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Promise<Boolean>.
  def async_content_warning?
    async_network_privilege.then do |privilege|
      next false unless privilege
      privilege.content_warning_category.present?
    end
  end

  # Public: Does this repository have a content warning?
  #         Stafftools can revoke privilege of easy visibility.
  #
  # Returns a Boolean.
  def content_warning?
    async_content_warning?.sync
  end

  def async_content_warning
    async_network_privilege.then do |privilege|
      next nil unless privilege
      next nil unless privilege.content_warning_category.present?
      cw = ActiveSupport::OrderedOptions.new
      cw.type = TrustSafety::ContentWarnings.type_for(privilege.content_warning_category)
      cw.category = privilege.content_warning_category
      cw.sub_category = privilege.content_warning_sub_category
      cw.custom_sub_category = privilege.content_warning_custom_sub_category
      cw
    end
  end

  def content_warning
    async_content_warning.sync
  end

  def apply_content_warning_later(category, *args, **kwargs)
    type = TrustSafety::ContentWarnings.type_for(category)
    raise StandardError.new("Invalid content warning category: #{category}") if type.nil?
    ApplyContentWarningJob.perform_later(self, category, *args, **kwargs)
    type
  end

  def remove_content_warning_later(**args)
    RemoveContentWarningJob.perform_later(self, **args)
    nil
  end

  # Returns the type of content warning that was applied, or nil if the content warning was removed.
  #
  # Do not call this method directly.
  # Instead, use `#apply_content_warning_later` or`#remove_content_warning_later`.
  def set_content_warning(
    category,
    sub_category = nil,
    custom_sub_category = nil,
    actor:,
    forks: false,
    notify_fork_owners: true,
    instructions: nil
  )
    repos = forks ? network.repositories : [self]

    repos.map do |repo|
      set_content_warning_on_repo(
        repo,
        category,
        sub_category,
        custom_sub_category,
        actor: actor,
        notify_fork_owners: true,
        instructions: instructions
      )
    end

    Stafftools::NetworkPrivilege.recalculate_trending_repos

    nil
  end

  private def set_content_warning_on_repo(
    repo,
    category,
    sub_category = nil,
    custom_sub_category = nil,
    actor:,
    forks: false,
    notify_fork_owners: true,
    instructions: nil
  )
    # Validation
    TrustSafety::ContentWarnings.validate_category(category, allow_nil: true)
    TrustSafety::ContentWarnings.validate_sub_category(category, sub_category, allow_nil: true)

    # Short circuit further code execution
    if category == repo&.network_privilege&.content_warning_category
      GitHub.logger.info("Skipping content warning update for #{repo.full_name} because it is already set to #{category}")
      return
    end

    # Some variables
    adding_content_warning = category.present?
    type = TrustSafety::ContentWarnings.type_for(category)

    # Update NetworkPrivilege table
    repo.network_privilege ||= Stafftools::NetworkPrivilege.new
    repo.network_privilege[:content_warning_category] = category
    repo.network_privilege[:content_warning_sub_category] = sub_category
    repo.network_privilege[:content_warning_custom_sub_category] = custom_sub_category

    repo.network_privilege[:hide_from_discovery] = adding_content_warning
    repo.network_privilege.save!

    # Send emails
    if adding_content_warning && (notify_fork_owners || !repo.fork?)
      RepositoryMailer.content_warning_notice(repo, category, instructions).deliver_later
    end

    # Write to audit log
    context = event_context.merge({
      content_warning_category: category,
      content_warning_sub_category: sub_category,
      content_warning_custom_sub_category: custom_sub_category
    })
    instrument "#{adding_content_warning ? "add" : "remove"}_content_warning", context

    # Publish hydro event
    if adding_content_warning
      GlobalInstrumenter.instrument "repository.apply_content_warning", {
        actor: actor,
        repository: repo,
        type: type.capitalize,
        category: category,
        sub_category: sub_category,
        custom_sub_category: custom_sub_category,
        notify_fork_owners: true,
        instructions: instructions,
      }
    else
      GlobalInstrumenter.instrument "repository.remove_content_warning", {
        actor: actor,
        repository: repo,
      }
    end
  end
end
