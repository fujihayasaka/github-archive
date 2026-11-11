# typed: true
# frozen_string_literal: true

module UserHovercard::Contexts
  class AdvisoryCredits < Hovercard::Contexts::Base
    attr_reader :user, :viewer, :credit_count

    def initialize(user:, viewer:, credit_count:)
      @user = user
      @viewer = viewer
      @credit_count = credit_count

      helpers.extend(ActionView::Helpers::NumberHelper)
      helpers.extend(UsersHelper)
    end

    def message
      "#{social_credit_count} security advisory #{"credit".pluralize(credit_count)}"
    end

    def octicon
      "shield"
    end

    def social_credit_count
      helpers.social_count(credit_count)
    end

    def platform_type_name
      "GenericHovercardContext"
    end

    private

    def helpers
      @helpers ||= Module.new
    end
  end
end
