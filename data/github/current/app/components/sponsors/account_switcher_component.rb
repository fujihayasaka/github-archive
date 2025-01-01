# typed: true
# frozen_string_literal: true

class Sponsors::AccountSwitcherComponent < ApplicationComponent
  MAX_ACCOUNTS_TO_FETCH = 100

  include AvatarHelper
  include SponsorsButtonsHelper

  # sponsor - the User or Organization acting as the sponsor, or someone who might start sponsoring
  # sponsorable - the User or Organization being sponsored, if there is only one
  # sponsorship - the Sponsorship from the given sponsor to the given sponsorable, if one exists
  # selected_tier - the SponsorsTier that the viewer has selected, if any
  # adminable_orgs_only - Boolean controlling whether any org the viewer belongs to should be listed in the
  #                       switcher (false) versus only orgs that the viewer can administer (true)
  # allow_selecting_invoiced_orgs - Boolean controlling whether invoiced orgs that aren't set up for invoiced
  #                                 sponsorship payments should be included in the list
  # path_params - optional Hash of additional parameters to pass to the route helper for each account link
  # form_data - Hash of additional data to use in the forms for each account, if method is `:post`
  # method - Symbol representing whether each link should be an `<a>` tag (default) or a button in a form;
  #          choose between `:get` and `:post`
  # route - Symbol representing which route helper to use for each link's URL or form's action
  # header_tag - Symbol representing which HTML tag to use for the header element of the switcher
  def initialize(sponsor:,
                sponsorable: nil,
                sponsorship: nil,
                selected_tier: nil,
                adminable_orgs_only: true,
                allow_selecting_invoiced_orgs: false,
                path_params: nil,
                form_data: nil,
                method: :get,
                route: :sponsorable,
                header_tag: :h4)
    @sponsorable = sponsorable
    @sponsor = sponsor
    @sponsorship = sponsorship
    @selected_tier = selected_tier
    @adminable_orgs_only = adminable_orgs_only
    @allow_selecting_invoiced_orgs = allow_selecting_invoiced_orgs
    @path_params = path_params || {}
    @form_data = form_data || {}
    @method = method
    @route = route
    @header_tag = header_tag
  end

  private

  def render?
    logged_in? && GitHub.sponsors_enabled? && @sponsor.present?
  end

  def invoice_billing_contact_us_url
    SponsorsListing.support_url(subject: SponsorsPrimerMailer::INVOICE_BALANCE_SUPPORT_SUBJECT)
  end

  memoize def eligible_accounts
    accounts_by_eligibility[:eligible]
  end

  def ineligible_invoiced_accounts
    accounts_by_eligibility[:ineligible_invoiced]
  end

  memoize def accounts_by_eligibility
    return { eligible: accounts, ineligible_invoiced: [] } if @allow_selecting_invoiced_orgs

    # NOTE: we check `invoiced?` on all accounts, which requires `business` in some cases
    #       by batching all those calls we avoid an N+1
    GitHub::PrefillAssociations.prefill_batch_method(accounts, :async_business)

    accounts.each_with_object({
      eligible: [],
      ineligible_invoiced: [],
    }) do |account, result|
      is_ineligible_invoiced = account.invoiced? && !account.sponsors_invoiced?
      eligibility = is_ineligible_invoiced ? :ineligible_invoiced : :eligible
      result[eligibility].push(account)
    end
  end

  memoize def accounts
    result = current_user.potential_sponsor_accounts.limit(MAX_ACCOUNTS_TO_FETCH).to_a

    unless @adminable_orgs_only
      remainder_limit = [0, MAX_ACCOUNTS_TO_FETCH - result.count].max

      member_orgs = current_user.organizations
        .where.not(id: result.map(&:id))
        .limit(remainder_limit)
        .to_a

      result += member_orgs
    end

    # It's not possible to sponsor an org as that org, so we omit it from the list.
    # As a user you can't sponsor yourself, but you can preview the checkout process.
    if @sponsorable&.organization?
      result.reject! { |account| account == @sponsorable }
    end

    result
  end

  memoize def path_params
    result = @path_params.merge(tier_id: @selected_tier&.id)

    result[:frequency] = params[:frequency] if params[:frequency]

    if @selected_tier&.new_record?
      result[:amount] = custom_tier_amount
    end

    if pass_new_custom_tier_params?
      result[:tier_id] = nil
      result[:amount] = custom_tier_amount
      result[:frequency] = custom_tier_frequency
    end

    result
  end

  # Private: To make use of the selected tier, should we pass parameters to let the viewer
  # create a new, equivalent custom tier instead of trying to reuse the same tier?
  #
  # Returns a Boolean.
  def pass_new_custom_tier_params?
    return false unless @selected_tier&.custom?
    @selected_tier.new_record? || !@selected_tier.readable_by?(current_user)
  end

  memoize def locked_sponsorship_exists_by_sponsor_id
    return Hash.new(false) unless @sponsorable
    Hash.new(false).merge(
      Sponsorship
        .locked
        .from_sponsor(eligible_accounts.map(&:id))
        .with_user_or_org_sponsorable(@sponsorable)
        .pluck(:sponsor_id)
        .map { |sponsor_id| [sponsor_id, true] }
        .to_h
    )
  end

  def locked_sponsorship_exists_for_sponsor?(account)
    return true if account == @sponsor && @sponsorship&.locked?
    locked_sponsorship_exists_by_sponsor_id[account.id]
  end

  memoize def custom_tier_amount
    return unless @selected_tier&.custom?
    @selected_tier.monthly_price_in_dollars.to_i
  end

  memoize def custom_tier_frequency
    return unless @selected_tier&.custom?
    @selected_tier.one_time? ? "one-time" : "recurring"
  end

  memoize def hydro_attrs
    return {} unless @sponsorable
    sponsors_button_hydro_attributes(:ACCOUNT_SWITCHER_OPEN, @sponsorable.display_login)
  end
end
