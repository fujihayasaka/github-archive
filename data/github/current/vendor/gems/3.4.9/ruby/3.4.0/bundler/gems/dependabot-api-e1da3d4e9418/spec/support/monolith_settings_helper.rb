# frozen_string_literal: true

module MonolithSettingsHelper
  def stub_monolith_settings(settings = {})
    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(
        instance_double(
          GitHub::Twirp::DependabotRepositorySettings,
          get_repository_settings: OpenStruct.new(**settings)
        )
      )
  end
end
