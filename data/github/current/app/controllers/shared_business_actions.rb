# typed: true
# frozen_string_literal: true

module SharedBusinessActions
  extend T::Helpers
  requires_ancestor { ApplicationController }

  def check_slug
    slug = params[:value] || ""
    return head 400 if slug.blank?

    error_message = if !slug.match?(Business::SLUG_REGEX)
      "'#{slug.presence}' #{Business::SLUG_VALIDATION_MESSAGE}."
    elsif slug.length > Business::MAX_SLUG_LENGTH
      "'#{slug}' is too long (maximum is #{Business::MAX_SLUG_LENGTH} characters)"
    end

    unless error_message
      already_taken = Business.including_deleted.find_by(slug: slug).present?
    end

    status = error_message || already_taken ? 422 : 200

    respond_to do |format|
      format.html_fragment do
        render \
          Businesses::SlugMessageComponent.new(
            slug: slug,
            already_taken: already_taken,
            error_message: error_message
          ), layout: false, formats: :html, status: status
      end
    end
  end

  def check_shortcode
    shortcode = params[:value].to_s.downcase || ""
    return head 400 if shortcode.blank?

    error_message = if !shortcode.match?(Business::SHORTCODE_REGEX)
      "'#{shortcode}' #{Business::SHORTCODE_VALIDATION_MESSAGE}."
    elsif shortcode.length > Business::MAX_SHORTCODE_LENGTH && !GitHub.flipper[:any_length_shortcode].enabled?(current_user)
      "'#{shortcode}' is too long (maximum is #{Business::MAX_SHORTCODE_LENGTH} characters)"
    end

    unless error_message
      already_taken = \
        Business.including_deleted.find_by(shortcode: shortcode).present? \
        || Business::ORPHANED_SHORTCODES.include?(shortcode)
    end

    status = error_message || already_taken ? 422 : 200

    respond_to do |format|
      format.html_fragment do
        render \
          Businesses::ShortcodeMessageComponent.new(
            shortcode: shortcode,
            already_taken: already_taken,
            error_message: error_message
          ), layout: false, formats: :html, status: status
      end
    end
  end

  def check_billing_email
    billing_email = params[:value]
    return head 400 if billing_email.blank?

    # we want to fail early and give some feedback if the user tries to add an email that appears
    # on the sanctioned list.
    if billing_email =~ UserEmail::MarketingDependency::EMAIL_REGEX && !::TradeControls::Domains.sanctioned_email?(billing_email)
      respond_to do |format|
        format.html_fragment do
          head 200
        end
      end
    else
      respond_to do |format|
        format.html_fragment do
          render body: "Email is invalid", status: 422, content_type: "text/fragment+html"
        end
      end
    end
  end
end
