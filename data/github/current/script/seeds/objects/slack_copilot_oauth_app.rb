# typed: true
# frozen_string_literal: true

# Do not require anything here. If you need something else, require it in the method that needs it.
# This makes sure the boot time of our seeds stays low.

module Seeds
  module Objects
    class SlackCopilotOauthApp
      def self.create(owner:, integration_url:, output_file: nil)
        integration_url ||= ENV.fetch("SLACK_INTEGRATION_URL", "http://localhost:4567")
        app_name = "Slack Copilot (Dev)"
        callback_url = "#{integration_url}/github/oauth/callback"

        application = OauthAccessTokens.domain.oauth_applications.by_user_and_name(owner, app_name)
        if application
          puts "> Using existing OAuth application: #{application.name}"
          updates = {}
          if application.callback_url != callback_url
            puts "> Updating callback URL to #{callback_url}"
            updates[:callback_url] = callback_url
          end
          if application.url != integration_url
            puts "> Updating integration URL to #{integration_url}"
            updates[:url] = integration_url
          end
          application.update!(updates) if updates.any?
        else
          puts "> Creating OAuth application: #{app_name}"
          application = ::OauthApplication.create!(
            user: owner,
            name: app_name,
            url: integration_url,
            callback_url: callback_url,
          )
        end

        secret = application.generate_client_secret(creator: owner)

        env_vars = <<~EOF
        SLACK_COPILOT_GITHUB_OAUTH_APPLICATION_ID=#{application.id}
        SLACK_COPILOT_GITHUB_OAUTH_CLIENT_ID=#{application.key}
        SLACK_COPILOT_GITHUB_OAUTH_CLIENT_SECRET=#{secret.secret}
        EOF

        puts env_vars
        append_to_file(file: output_file, content: env_vars) if output_file.present?

        application
      end

      def self.append_to_file(file:, content:)
        File.open(file, "a") { |f| f.write(content) }
      end
      private_class_method :append_to_file
    end
  end
end
