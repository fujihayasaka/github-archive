# typed: true
# frozen_string_literal: true

class Sponsors::AccountSwitcher::ItemComponent < ApplicationComponent
  METHODS = %i(get post).freeze
  DEFAULT_METHOD = :get
  GENERAL_ROUTES = %i(sponsorable sponsorships).freeze
  BULK_SPONSORSHIP_ROUTES = %i(bulk_sponsorship_new bulk_sponsorship_edit bulk_sponsorship_checkout bulk_sponsorship_frequencies).freeze
  ROUTES = (GENERAL_ROUTES + BULK_SPONSORSHIP_ROUTES).freeze
  DEFAULT_ROUTE = :sponsorable

  # sponsor - User or Organization acting as the sponsor
  # sponsorable - User or Organization being sponsored
  # is_selected - Boolean indicating whether the given sponsor the currently selected one
  # locked_sponsorship_exists_for_sponsor - Boolean indicating whether the sponsor has a locked sponsorship
  #                                         for the given sponsorable
  # path_params - Hash of additional params to pass to the path helper for the sponsor link
  # form_data - Hash of additional data to use in the form for this sponsor, if method is `:post`
  # method - Symbol representing whether to render an `<a>` tag (default) or a button in a form;
  #          choose between `:get` and `:post`
  # route - Symbol representing which route helper to use for the link's URL or form's action
  # content_arguments - Used when rendering the `Primer::Alpha::ActionList::Item` component
  # system_arguments – Primer system arguments to pass into `Primer::Alpha::ActionList::Item`
  sig do
    params(
      sponsor: GitHubSponsors::Types::Sponsor,
      sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable),
      is_selected: T::Boolean,
      locked_sponsorship_exists_for_sponsor: T::Boolean,
      path_params: T::Hash[T.untyped, T.untyped],
      form_data: Sponsors::BulkSponsorshipRow::FormData,
      method: Symbol,
      route: Symbol,
      content_arguments: T::Hash[T.untyped, T.untyped],
      system_arguments: T.untyped,
    ).void
  end
  def initialize(
    sponsor:,
    sponsorable: nil,
    is_selected: false,
    locked_sponsorship_exists_for_sponsor: false,
    path_params: {},
    form_data: {},
    method: DEFAULT_METHOD,
    route: DEFAULT_ROUTE,
    content_arguments: {},
    **system_arguments
  )
    @sponsor = sponsor
    @sponsorable = sponsorable
    @is_selected = is_selected
    @locked_sponsorship_exists_for_sponsor = locked_sponsorship_exists_for_sponsor
    @path_params = path_params
    @form_data = form_data
    @method = fetch_or_fallback(METHODS, method, DEFAULT_METHOD)
    @route = fetch_or_fallback(ROUTES, route, DEFAULT_ROUTE)
    @content_arguments = content_arguments
    @system_arguments = system_arguments
  end

  def call
    if method == :get
      render Primer::Alpha::ActionList::Item.new(
        **T.unsafe({
          href: url,
          active: selected?,
          test_selector: "sponsor-account-#{sponsor.display_login}",
          content_arguments: @content_arguments,
          **@system_arguments
        }),
      ).with_content(link_contents)
    elsif selected?
      render Primer::Alpha::ActionList::Item.new(
        **T.unsafe({
          active: true,
          test_selector: "sponsor-account-#{sponsor.display_login}",
          content_arguments: @content_arguments,
          **@system_arguments
        }),
      ).with_content(link_contents)
    else
      render Primer::Alpha::ActionList::Item.new(
        **T.unsafe({
          href: url,
          test_selector: "sponsor-account-#{sponsor.display_login}",
          form_arguments: {
            method: method,
            inputs: component_formatted_inputs_for(form_data),
          },
          content_arguments: @content_arguments,
          **@system_arguments
        }),
      ).with_content(link_contents)
    end
  end

  private

  attr_reader :sponsor, :sponsorable, :method, :form_data, :route

  def render?
    if sponsorable.blank?
      return false if [:sponsorable, :sponsorships].include?(route)
    end
    logged_in?
  end

  def link_contents
    safe_join([
      helpers.avatar_for(sponsor, 20, class: "avatar mr-1", aria: { hidden: true }),
      sponsor.display_login,
    ])
  end

  # Private: The form data, formatted to be used with the `Primer::Alpha::ActionList::Item` component.
  sig do
    params(
      data: T::Hash[T.untyped, T.untyped],
      parent_key: T.nilable(String),
    ).returns(T::Array[T::Hash[Symbol, T.untyped]])
  end
  def component_formatted_inputs_for(data, parent_key: nil)
    form_inputs = T.let([], T::Array[T.untyped])

    data.each do |key, value|
      current_key = parent_key ? "#{parent_key}[#{key}]" : key.to_s

      if value.is_a?(Hash)
        form_inputs += component_formatted_inputs_for(value, parent_key: current_key)
      elsif value.is_a?(Array)
        value.each do |item|
          form_inputs << { name: "#{current_key}[]", value: item }
        end
      else
        form_inputs << { name: current_key, value: value }
      end
    end

    form_inputs
  end

  def url
    case route
    when :sponsorable
      sponsorable_path(sponsorable, path_params)
    when :sponsorships
      sponsorable_sponsorships_path(sponsorable, path_params)
    when :bulk_sponsorship_new
      new_sponsors_bulk_sponsorship_imports_path(path_params)
    when :bulk_sponsorship_edit
      sponsors_bulk_sponsorship_imports_path(path_params)
    when :bulk_sponsorship_checkout
      sponsors_bulk_sponsorship_checkout_path(path_params)
    when :bulk_sponsorship_frequencies
      sponsors_bulk_sponsorship_frequencies_path(path_params)
    end
  end

  def path_params
    result = @path_params.merge(sponsor: sponsor.display_login)
    if locked_sponsorship_exists_for_sponsor?
      result[:editing] = nil
    end
    result
  end

  def bulk_sponsorship_route?
    BULK_SPONSORSHIP_ROUTES.any?(route)
  end

  def selected?
    @is_selected
  end

  def locked_sponsorship_exists_for_sponsor?
    @locked_sponsorship_exists_for_sponsor
  end
end
