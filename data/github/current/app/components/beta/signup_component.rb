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
      FeatureFlag.vexi.enabled?(beta.feature_slug, current_user, default: false)
    end

    def changelog_link_url
      if beta.respond_to?(:changelog_link_url)
        beta.changelog_link_url
      end
    end

    def hide_survey_single_checkbox
      if beta.respond_to?(:hide_survey_single_checkbox)
        beta.hide_survey_single_checkbox
      else
        false
      end
    end

    def preview_type
      if beta.respond_to?(:preview_type)
        beta.preview_type
      else
        # By default, we assume that this is a "technology preview", which is perhaps synonymous with technical preview
        # See: https://github.com/github/product/discussions/1665
        "technology preview"
      end
    end

    memoize def membership_exists?
      waitlist.exists?(member: current_user)
    end
  end
end
