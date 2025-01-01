# typed: true
# frozen_string_literal: true

class Spark::DashboardController < Spark::AbstractController
  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:show]
  )

  def show
    context_region_preset :spark

    render_react_app(
      title: "Spark",
      app_payload_generator: -> { app_payload },
      page_data: {
        hide_footer: true,
      },
      disable_ssr: true,
      app_name: "spark",
    )
  end

  private

  def app_payload
    {
      copilotChatSettingEnabled: false,
      searchWorkerFilePath: helpers.find_file_worker_path,
      ssoOrganizations: sso_organizations,
      copilotUpsellBannerDismissed: false,
      graphqlApiUrl: "/copilot/pipes/pipes_execution",
      previewUrl: Viewscreen.host_url,
      **helpers.copilot_chat_payload(false, saml_authorized_organizations(cap_filter, current_user), request),
    }.merge({ icebreakers: icebreakers_json })
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def icebreakers_json
    file_path = Rails.root.join("config/spark-icebreakers.json")
    data = JSON.parse(File.read(file_path))
    [
      { type: "functional", data: data["functional"] || [] },
      { type: "instructional", data: data["instructional"] || [] },
      { type: "interactional", data: data["interactional"] || [] }
    ]
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
