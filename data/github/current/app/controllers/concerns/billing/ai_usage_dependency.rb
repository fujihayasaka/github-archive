# typed: strict
# frozen_string_literal: true

module Billing::AiUsageDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(current_user: T.nilable(User)).void }
  def ensure_ai_usage_enabled(current_user:)
    render_404 unless FeatureFlag.vexi.enabled?(:copilot_token_based_billing, current_user, default: false)
  end

  sig { params(entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).void }
  def respond_with_ai_usage(entity:, is_stafftools_route: false)
    selected_link = entity.is_a?(Business) ? :business_billing_vnext_ai_usage : :billing_vnext_ai_usage

    respond_with_react(
      payload: {},
      page_data: { selected_link: selected_link, sidebar: :billing_and_licensing },
      layout: react_layout(entity, is_stafftools_route),
      title: "AI usage"
    )
  end

  sig { params(entity: ::Billing::Types::Account, is_stafftools_route: T::Boolean).returns(T.any(Symbol, String)) }
  def react_layout(entity, is_stafftools_route)
    if is_stafftools_route
      :default
    elsif entity.is_a?(Business)
      "react_business"
    elsif entity.is_a?(Organization)
      "organization_settings"
    else
      "user_settings"
    end
  end
end
