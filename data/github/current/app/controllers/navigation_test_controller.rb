# typed: true
# frozen_string_literal: true

class NavigationTestController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  before_action :require_feature_flags
  before_action :login_required


  def rails # rubocop:todo GitHub/UseRestfulActions
    render "navigation_test/rails"
  end

  def react # rubocop:todo GitHub/UseRestfulActions
    data = params[:data]
    kind = params[:kind]

    title_data = case data
    when "json" then "React"
    when "relay" then "React-Relay"
    end

    title_kind = case kind
    when "ssr" then "SSR"
    when "csr" then "CSR"
    when "transition_while_fetching" then "Transition While Fetching"
    end

    title = "#{title_data} #{title_kind}"
    ssr = kind == "ssr"
    sleep 0.2 if request&.xhr? # allows test to see loading state. May need to play wit this if tests are flakey


    render_react_app(
      title: page_title(title),
      disable_ssr: !ssr,
      payload: { title: title, someField: "someValue", ssr: ssr },
    )
  end

  private

  def page_title(title)
    "#{title} · Navigation Test"
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_feature_flags
    render_404 unless FeatureFlag.vexi.enabled?(:navigation_test, current_user, default: false)
  end
end
