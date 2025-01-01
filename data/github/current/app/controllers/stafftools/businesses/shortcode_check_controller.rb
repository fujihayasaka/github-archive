# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::ShortcodeCheckController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :business_required
  before_action :check_for_orphaned_shortcode_collision, only: [:create]

  def create
    return head 400 if shortcode_from_params.blank?

    sample_business = Business.new(
      name: "test",
      slug: "test",
      business_type: :enterprise_managed,
      shortcode: shortcode_from_params,
      any_length_shortcode_feature_flag_enabled: current_user_can_set_any_length_shortcode?
    )
    unless sample_business.valid?
      error_msg = sample_business.errors[:shortcode].first
    end

    if error_msg.present?
      render status: 422, plain: "'#{shortcode_from_params}' #{error_msg}"
    else
      render \
        status: 200,
        plain: "The enterprise managed users in this enterprise will \
          be created with login handles like monalisa_#{shortcode_from_params}".squish
    end
  end

  private

  def check_for_orphaned_shortcode_collision
    return if shortcode_from_params.blank?

    if Business::ORPHANED_SHORTCODES.include?(shortcode_from_params)
      render status: 422, plain: "'#{shortcode_from_params}' is already taken by another enterprise account"
    end
  end

  memoize def shortcode_from_params
    params[:value].to_s.downcase
  end

  memoize def current_user_can_set_any_length_shortcode?
    GitHub.flipper[:any_length_shortcode].enabled?(current_user)
  end
end
