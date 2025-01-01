# typed: true
# frozen_string_literal: true

class Codespaces::DropdownListItemComponent < ApplicationComponent
  with_collection_parameter :codespace

  include CodespacesHelper
  include GitHub::Memoizer
  include PullRequestsHelper

  attr_reader :codespace, :access_result, :tag, :event_target, :repository, :show_commit_divergence, :is_read_only, :needs_fork_to_push

  # codespace             - The codespace to be rendered
  # tag                   - Element type of the root node - default is "li"
  # access_result         - A Codespaces::Access::AllowedResult object for the codespace indicating usage allowed, or explaining why not
  # event_target          - a symbol explaining expressing where this component is displayed, either :PULL_REQUEST_PAGE_DROPDOWN or :REPO_PAGE_DROPDOWN

  def initialize(
    codespace:,
    tag: "li",
    access_result:,
    repository:,
    event_target:,
    is_read_only:,
    needs_fork_to_push: false,
    show_commit_divergence: true,
    delete_confirmation_message:
  )

    @codespace, @tag, @access_result, @repository, @event_target, @is_read_only, @needs_fork_to_push, @show_commit_divergence, @delete_confirmation_message =
      codespace, tag, access_result, repository, event_target, is_read_only, needs_fork_to_push, show_commit_divergence, delete_confirmation_message
  end

  def is_read_only?
    is_read_only
  end

  def is_for_fork?
    repository.id == codespace.repository.parent_id
  end

  def link_disabled?
    !access_result.allowed? || codespace.blocking_operation?
  end

  def codespace_link_params
    link_disabled? ? ["span", default_link_attributes] : ["a", link_enabled_attributes]
  end

  def default_link_classes
    "d-block"
  end

  def default_link_attributes
    {
      class: class_names(default_link_classes),
      id: codespace.name
    }.merge(test_selector_data_hash("codespaces-open-codespace-link"))
  end

  def link_enabled_attributes
    default_link_attributes
      .merge({ class: class_names(
        default_link_classes,
        "p-0", "mt-0",
        "color-fg-muted",
        "Link--muted",
        "no-underline"
      ) })
      .merge({ href: codespace_url_from_editor_preferences(codespace: codespace, user: current_user) })
      .merge({ data: { "turbo" => false }.merge(open_codespace_attributes(codespace: codespace, target: event_target)) })
  end

  def codespace_url_text
    "Open #{codespace.display_name} in #{current_user.codespace_preferred_editor}"
  end

  def codespace_link_html(&block)
    content_tag(*codespace_link_params, &block)
  end

  def show_display_name?
    codespace.display_name.present?
  end

  def role
    "menuitem" if @tag == "li"
  end

  def fork_title(prepend)
    "#{prepend} #{codespace.repository.name_with_display_owner}"
  end

  def no_permission_copy
    "You don't have push permissions"
  end

  def needs_machine_type_change?
    access_result.disallowed_by_machine_policy?
  end

  def needs_base_image_change?
    access_result.disallowed_by_image_policy?
  end

  def show_active_label?
    codespace.consuming_compute?
  end

  def show_failed_label?
    codespace.creation_failed?
  end

  def pull_request_icon
    case
    when codespace.pull_request.merged?
      "git-merge"
    when codespace.pull_request.closed?
      "git-pull-request-closed"
    else
      "git-pull-request"
    end
  end
end
