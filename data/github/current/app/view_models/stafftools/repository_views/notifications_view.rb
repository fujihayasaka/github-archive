# typed: false
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class NotificationsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :repository
      attr_reader :user
      attr_reader :request
      attr_reader :params

      def page_title
        "#{repository.name_with_owner} - Notifications"
      end

      def kusto_db
        "hydro"
      end

      def notification_delivery_kusto_query(handler = nil, pipeline = nil)
        kusto_table = if pipeline == :notifyd
          "notifyd_v0_delivered_notification"
        else
          "github_notifications_v0_notification_delivery"
        end

        query_params = current_params.inject([]) do |arr, (key, value)|
          case key.to_sym
          when :user
            if pipeline == :notifyd
              arr << "user.id == '#{user.id}'" if user
            else
              arr << "user_id == '#{user.id}'" if user
            end
          when :thread, :comment
            type, id = value.split(";")
            if pipeline == :notifyd
              arr << "| where tracking.subject_metadata.#{key}_type == '#{type}' and tracking.subject_metadata.#{key}_id == '#{id}'"
            else
              arr << "| where #{key}_type == '#{type}' and #{key}_id == '#{id}'"
            end
          end

          arr
        end

        if pipeline == :notifyd
          query_params << "| where tracking.subject_metadata.list_type == 'Repository' and tracking.subject_metadata.list_id == '#{repository.id}'" if repository
          query_params << "| where channel == '#{handler.upcase}'" if handler
        else
          query_params << "| where list_type == 'Repository' and list_id == '#{repository.id}'" if repository
          query_params << "| where handler == '#{handler.upcase}'" if handler
        end

        <<~KQL
          #{kusto_table}
          // Uncomment just one of the timestamp filters depending on your requirements
          | where timestamp > ago(3d)
          // | where timestamp between (todatetime('2024-07-22T06:00:00Z') .. todatetime('2024-07-22T20:00:00Z'))
          #{query_params.join("\n").chomp}
          | take 100
        KQL
      end

      def notification_delivery_splunk_query(handler = nil, pipeline = nil)
        splunk_index = if pipeline == :notifyd
          "notifyd"
        elsif GitHub.multi_tenant_enterprise?
          "prod-resque"
        else
          "prod-notifications"
        end

        splunk_params = current_params.inject([]) do |arr, (key, value)|
          case key.to_sym
          when :user
            arr << "gh.user.id=#{user.id}" if user
          when :thread, :comment
            type, id = value.split(";")
            if pipeline == :notifyd
              arr << "gh.notifyd.#{key}.type=#{type} gh.notifyd.#{key}.id=#{id}"
            else
              arr << "gh.notifications.delivery.#{key}.type=#{type} gh.notifications.delivery.#{key}.id=#{id}"
            end
          end

          arr
        end

        if pipeline == :notifyd
          splunk_params << "gh.notifyd.list.type=Repository gh.notifyd.list.id=#{repository.id}" if repository
          splunk_params << "gh.notifyd.channel=#{handler}" if handler
        else
          splunk_params << "gh.notifications.delivery.list.type=Repository gh.notifications.delivery.list.id=#{repository.id}" if repository
          splunk_params << "gh.notifications.handler=#{handler}" if handler
        end

        msg_body = if pipeline == :notifyd
          "Body=\"notification delivered\""
        else
          # Temporary until the old message drops out of retention.
          # Can be changed to `notification delivered` on 31/05/2025 (180 days from 02/12/2024).
          "(Body=\"notification delivered\" OR Body=\"delivered notification\")"
        end

        "index=#{splunk_index} #{msg_body} #{splunk_params.join(" ")}".strip
      end

      private

      def current_params
        return @current_params if defined?(@current_params)

        @current_params = params
          .slice(:thread, :comment, :handler, :user, :before)
          .to_hash
          .with_indifferent_access

        if params[:issue]
          issue = repository.issues.find_by_number(params[:issue])
          @current_params[:thread] = "Issue;#{issue && issue.id}"
        end

        @current_params
      end
    end
  end
end
