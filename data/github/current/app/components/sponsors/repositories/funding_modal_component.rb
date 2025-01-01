# typed: true
# frozen_string_literal: true

class Sponsors::Repositories::FundingModalComponent < ApplicationComponent
  # owner_login - login of the Repository owner where the funding modal is being shown
  # repo_name - name of the Repository where the funding modal is being shown
  # auto_open_url_param - optional String URL parameter where, if specified and it's present in the URL when the page
  #                       containing this view component is rendered, the funding modal will be opened automatically
  # is_sponsoring - Boolean indicating whether the viewer is sponsoring the repo owner or one of the other
  #                 GitHub Sponsors users/orgs listed in the repository's funding.yml file
  # modal_id - optional DOM ID for uniquely identifying the modal
  # icon_button - A Boolean indicating whether the button should be rendered as an icon button
  # button_id - optional DOM ID for uniquely identifying the button for correct tooltip placement
  # system_arguments - optional Hash of Primer system attributes to apply to the outermost `<details>`.
  #                    See https://primer.style/view-components/system-arguments
  sig do
    params(
      owner_login: String,
      repo_name: String,
      auto_open_url_param: T.nilable(String),
      is_sponsoring: T::Boolean,
      modal_id: T.nilable(String),
      icon_button: T::Boolean,
      button_id: T.nilable(String),
      system_arguments: Primer::SystemArgumentsValue,
    ).void
  end
  def initialize(owner_login:, repo_name:, auto_open_url_param: nil, is_sponsoring: false, modal_id: nil, icon_button: false, button_id: "sponsor-button", **system_arguments)
    @owner_login = owner_login
    @repo_name = repo_name
    @name_with_owner = T.let("#{owner_login}/#{repo_name}", String)
    @auto_open_url_param = auto_open_url_param
    @is_sponsoring = is_sponsoring
    @modal_id = T.let(modal_id || "funding-links-modal-#{owner_login}-#{repo_name}", String)
    @icon_button = icon_button
    @button_id = button_id
    @system_arguments = system_arguments
  end

  private

  attr_reader :owner_login, :repo_name, :name_with_owner, :modal_id, :button_id, :system_arguments,
    :auto_open_url_param

  sig { returns String }
  def button_aria_label
    prefix = sponsoring? ? "Sponsoring" : "Sponsor"
    "#{prefix} #{name_with_owner}"
  end

  sig { returns Symbol }
  memoize def icon_for_button
    sponsoring? ? :"heart-fill" : :heart
  end

  sig { returns T::Boolean }
  def icon_button?
    @icon_button
  end

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled? && owner_login.present? && repo_name.present?
  end

  sig { returns T::Boolean }
  def sponsoring?
    @is_sponsoring
  end

  sig { params(selector: String).returns(String) }
  def button_test_selector(selector)
    icon_button? ? "#{selector}-icon-button" : "#{selector}-button"
  end

  sig { returns T.nilable(String) }
  memoize def button_text
    return if icon_button?
    sponsoring? ? "Sponsoring" : "Sponsor"
  end

  sig { returns T.nilable(ActiveSupport::SafeBuffer) }
  def button_content
    return if button_text.blank?
    safe_join([
      primer_octicon(
        icon: icon_for_button,
        mr: 1,
        color: :sponsors,
        classes: class_names("icon-sponsoring" => sponsoring?, "icon-sponsor" => !sponsoring?),
      ),
      render(Primer::BaseComponent.new(tag: :span).with_content(button_text)),
    ], " ")
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  def button_attrs
    {
      icon: icon_button? ? icon_for_button : nil,
      id: button_id,
      "aria-label": button_aria_label,
      size: :small,
      test_selector: button_test_selector("sponsor-modal"),
    }
  end

  sig { returns ActiveSupport::SafeBuffer }
  def body_content
    render(Primer::Alpha::IncludeFragment.new(
      preload: true,
      src: funding_links_path(owner_login, repo_name, fragment: 1),
    ).with_content(render(Primer::Beta::Spinner.new(
      size: :large,
      my: 3,
      mx: :auto,
      display: :block,
      "aria-label": "Loading...",
    ))))
  end

  sig { returns T::Hash[T.any(Symbol, String), T.untyped] }
  def dialog_attrs
    { title: "Sponsor #{name_with_owner}", id: modal_id }.merge(system_arguments)
  end
end
