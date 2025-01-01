# typed: true
# frozen_string_literal: true

class Codespaces::DisabledButtonComponent < ApplicationComponent
  include CodespacesHelper

  attr_reader :btn_class, :cap_filter, :current_user, :at_limit, :text, :codespace, :force_render, :is_spoofed_commit

  # btn_class                       - a CSS class String to use for the button element.
  # cap_filter                      - cap_filter from helper method, passing it in so we can use it before render
  # current_user                    - current_user from helper method, passing it in so we can use it before render
  # at_limit                        - Is the user at their codespace limit?
  # codespace                       - Used to calculate if pushable or forkable
  # tooltip_class                   - a CSS class that will be applied to the <button> element while it's disabled. Optional
  # is_spoofed_commit               - whether the built codespace seems to be on a spoofed commit (optional, default: false)

  def initialize(
    btn_class:,
    cap_filter:,
    current_user:,
    at_limit:,
    text:,
    codespace:,
    tooltip_class: nil,
    force_render: false,
    is_spoofed_commit: false
  )
    @btn_class = btn_class
    @cap_filter = cap_filter
    @current_user = current_user
    @at_limit = at_limit
    @text = text
    @codespace = codespace
    @tooltip_class = tooltip_class
    @force_render = force_render
    @is_spoofed_commit = is_spoofed_commit
  end

  def codespace_creation_disabled?
    GitHub.flipper[:disable_codespace_creation].enabled?(current_user)
  end

  def tooltip_class
    return @tooltip_class if @tooltip_class.present? && !at_total_usage_limit?
    if codespace_creation_disabled? || !usage_allowed?
      "tooltipped tooltipped-w"
    end
  end

  memoize def render?
    codespace_creation_disabled? ||
                !can_push_or_fork_repo? ||
                disable_at_limit? ||
                !usage_allowed? ||
                at_total_usage_limit? ||
                has_unsatisfied_cap? ||
                is_spoofed_commit ||
                has_ip_allowlists? ||
                closed_pull_request? ||
                force_render
  end

  def can_push_or_fork_repo?
    codespace.nil? || codespace.repository.pushable_by?(current_user) || current_user.can_fork?(codespace.repository)
  end

  def has_ip_allowlists?
    repository = codespace.repository
    return false unless repository.owner&.organization?

    repository.owner&.ip_allowlist_enabled? || repository.owner&.ip_allowlist_enabled_on_business?
  end

  # Checks if the user has reached their limit of number of accessible
  # codespaces, at which point we want to disallow new codespace creation.
  #
  # Returns Boolean
  def disable_at_limit?
    at_limit
  end

  def usage_allowed?
    return true if codespace.nil?

    usage_result.allowed?
  end

  memoize def at_total_usage_limit?
    if usage_result&.allowed?
      false
    elsif current_user.organization_ids.empty? # if the user has no usage allowed and no organizations then we are total usage limit
      true
    else
      # if any of the user's organizations have usage allowed then we are not at total usage limit
      !current_user.organizations.any? do |org|
        Codespaces::AccessChecker.new(org, user: current_user).allowed_by_billing?
      end
    end
  end

  def has_unsatisfied_cap?
    return false unless codespace

    cap_filter.unauthorized([codespace]).any?
  end

  memoize def closed_pull_request?
    codespace.pull_request&.closed?
  end

  private

  def usage_result
    return nil if codespace.nil?
    return @usage_result if defined?(@usage_result)
    Codespaces::AccessChecker.from_codespace(codespace).run_billing_check
  end
end
