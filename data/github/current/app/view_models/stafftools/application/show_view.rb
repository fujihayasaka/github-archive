# typed: true
# frozen_string_literal: true

module Stafftools
  module Application
    class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include UrlHelpers

      attr_reader :user
      attr_reader :app

      def scopes
        app.scopes && app.scopes.join(",")
      end

      def page_title
        app.name
      end

      def created
        app.created_at.strftime "%F"
      end

      def total_users
        authorize_view = Oauth::AuthorizeView.new(application: app)
        authorize_view.application_user_range
      end

      def client_id
        app.key
      end

      def field(name)
        val = send name.downcase.gsub(" ", "_")
        val.blank? ? "(none)" : val
      end

      # This application is owned by the GitHub organization.
      def github_application?
        app.user.login == GitHub.trusted_oauth_apps_org_name
      end

      def state
        app.state.humanize
      end

      def suspended?
        app.suspended?
      end

      def suspend_title
        suspended? ? "Reactivate application" : "Suspend application"
      end

      def suspend_form(&block)
        if suspended?
          enable_stafftools_user_application_path(@user, app, &block)
        else
          suspend_stafftools_user_application_path(@user, app, &block)
        end
      end

      def has_marketplace_listing?
        listing.present?
      end

      # Needed to get slug from Oauth apps
      def listing
        @listing ||= Marketplace::Listing.for_integratables(id, nil).first
      end

      delegate :name,
        :id,
        :description,
        :rate_limit,
        :callback_url,
        :using_temporary_rate_limit?, to: :app

      def ghec_rate_limit
        ghec_rate_limit_config.limit
      end

      def ghec_rate_limit_runway
        ghec_rate_limit_config.runway
      end

      def owner_soft_deleted_org?
        owner = app.owner
        owner.is_a?(::Organization) && T.let(owner, ::Organization).soft_deleted?
      end

      private

      def ghec_rate_limit_config
        @ghec_rate_limit_config ||= begin
          context = Stafftools::RateLimitContext.new(
            nil,
            current_app: app,
            request_owner: app.owner,
          )

          Api::RateLimitConfiguration.for(
            Api::RateLimitConfiguration::DEFAULT_FAMILY,
            context,
          )
        end
      end
    end
  end
end
