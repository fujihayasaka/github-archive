# typed: true
# frozen_string_literal: true

module Beta
  class SignupComponent < ApplicationComponent
    attr_reader :beta, :membership

    delegate :waitlist, to: :beta
    delegate_missing_to :beta

    def initialize(beta:)
      @beta = beta
      @membership = PrereleaseProgramMember.new
    end

    def adminable_organizations
      if beta.respond_to?(:allow_org_sign_up) && beta.allow_org_sign_up
        helpers.adminable_organizations
      end
    end

    def survey_header
      if beta.respond_to?(:survey_header)
        beta.survey_header
      end
    end

    def survey_flash
      if beta.respond_to?(:survey_flash)
        beta.survey_flash
      end
    end

    def survey_flash_link_url
      if beta.respond_to?(:survey_flash_link_url)
        beta.survey_flash_link_url
      end
    end

    def survey_choice_detail_links
      if beta.respond_to?(:survey_choice_detail_links)
        beta.survey_choice_detail_links
      end
    end

    def feature_icon_image_tag
      return unless beta.feature_icon_path

      image_tag beta.feature_icon_path, alt: "#{beta.feature_name} icon", width: 128, class: "d-block width-fit"
    end

    def already_enabled?
      GitHub.flipper[beta.feature_slug].enabled?(current_user)
    end

    memoize def membership_exists?
      waitlist.exists?(member: current_user)
    end
  end
end
