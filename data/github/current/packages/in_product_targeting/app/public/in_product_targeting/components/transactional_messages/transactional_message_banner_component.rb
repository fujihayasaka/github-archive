# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module TransactionalMessages
      class TransactionalMessageBannerComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::TransactionalMessageConcern

        rescue_from StandardError, with: :nothing

        sig { returns(T.nilable(User)) }
        attr_reader :user

        sig { returns(Symbol) }
        attr_reader :page

        sig { returns(T.nilable(Organization)) }
        attr_reader :organization

        sig { returns(T.nilable(Business)) }
        attr_reader :enterprise

        sig { returns(T.nilable(TransactionalMessageConfig)) }
        attr_reader :message_config

        sig do
          params(
            user: User,
            page: Symbol,
            organization: T.nilable(Organization),
            enterprise: T.nilable(Business)
          ).void
        end
        def initialize(user:, page:, organization: nil, enterprise: nil)
          @user = user
          @page = page
          @organization = organization
          @enterprise = enterprise
          @message_config = T.let(nil, T.nilable(TransactionalMessageConfig))

          if @user.present?
            context = EligibilityContext.new(organization: @organization, enterprise: @enterprise)
            @message_config = transactional_message_for_page(@user, @page, context)
          end
        end

        sig { returns(T::Boolean) }
        def render?
          return false if @user.nil?
          return false if @message_config.nil?

          true
        end

        sig { returns(String) }
        def message_html
          return "" unless @message_config

          @message_config.to_html(helpers)
        end

        sig { returns(String) }
        def dismiss_path
          return "" unless @message_config

          dismiss_params = { nudge: true }
          dismiss_params[:group] = @message_config.nudge_group.to_s if @message_config.nudge_group.present?

          helpers.dismiss_notice_path(@message_config.nudge_id.to_s, dismiss_params)
        end

        sig { returns(String) }
        def nudge_id
          return "" unless @message_config

          @message_config.nudge_id.to_s
        end

        sig { returns(String) }
        def nudge_category
          return "" unless @message_config

          @message_config.nudge_category
        end

        sig { returns(String) }
        def nudge_group
          return "" unless @message_config

          @message_config.nudge_group.to_s
        end

        sig { returns(String) }
        def page_location
          @page.to_s
        end

        sig { returns(T.nilable(Integer)) }
        def banner_margin_top
          return 3 if @page == :org

          nil
        end

        # Analytics attributes for the visible event on the container
        sig { returns(T::Hash[String, String]) }
        def visible_analytics_data
          return {} unless @message_config

          helpers.analytics_visible_attributes(
            category: nudge_category,
            group: nudge_group,
          )
        end

        # Analytics attributes for the dismiss button click event
        sig { returns(T::Hash[String, String]) }
        def dismiss_analytics_data
          return {} unless @message_config

          helpers.analytics_click_attributes(
            category: nudge_category,
            action: "dismiss",
            location: page_location,
            group: nudge_group,
          )
        end
      end
    end
  end
end
