# typed: true
# frozen_string_literal: true

class Copilot::CopilotTraceViewerController < Copilot::Chat::AbstractChatController
  skip_before_action :require_feature_enabled
  before_action :require_trace_view_enabled
  before_action :require_staff
  before_action :require_trace_team

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]
  )

  def show
    user = T.must(current_user)
    thread_id = params[:thread_id]
    ccp = helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, user), request)

    respond_with_react(
      payload: ThreadViewRoutePayload.new(thread_id: thread_id),
      app_name: "copilot-trace-viewer",
      app_payload_generator: -> {
        {
          **ccp,
          thread_id: thread_id,
        }
      },
      title: "Trace View"
    )
  end

  private

  # resources are fetched from CAPI which handles authorization
  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # AbstractChatController requires a logged in user
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def require_trace_view_enabled
    render_404 unless current_user.feature_flag_enabled?(:copilot_coffe_trace_view_enabled, default: false)
  end

  def require_staff
    render_404 unless staff_bar_enabled?
  end

  def require_trace_team
    required_org = "github"
    required_team = "ai-core-dx-reviewers"
    org = Organization.find_by_login(required_org)
    team = org&.teams.find_by_slug(required_team)
    render_404 unless team && current_user && team.member?(current_user)
  end

  class ThreadViewRoutePayload < ReactPayload::Base
    def route_id
      "threadViewRoute"
    end

    def initialize(thread_id: nil)
      super()
      @thread_id = thread_id
    end

    def payload
      {
        thread_id: @thread_id,
      }
    end
  end
end
