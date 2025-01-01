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

      def notification_delivery_splunk_query(handler = nil)
        splunk_params = current_params.inject([]) do |arr, (key, value)|
          case key.to_sym
          when :user
            arr << "recipient=#{user.login}" if user
          when :thread, :comment
            type, id = value.split(";")
            arr << "#{key}_id=#{id} #{key}_type=#{type}"
          when :before
            arr << "delivered_at < #{value}"
          end

          arr
        end

        splunk_params << "list_type=Repository list_id=#{repository.id}" if repository
        splunk_params << "handler=#{handler}" if handler

        "index=prod-notifications #{splunk_params.join(" ")}".strip
      end

      def user?
        !user.nil?
      end

      def clear_filters?
        user? || current_params.key?(:thread) || current_params.key?(:comment)
      end

      def user_settings_title
        "#{user} Settings"
      end

      def all_notifications_title
        "All #{repository.name_with_owner} Notifications"
      end

      def all_notifications_params
        current_params.slice(:before, :handler)
      end

      def latest_notifications_params
        params = current_params.dup
        params.delete(:before)
        params
      end

      def notifications
        @notifications ||= begin
          notifications = recent_notifications.map do |notification|
            {
              repo_params: url_params,
              thread_key: notification.thread_key,
              thread_params: thread_params(notification),
              comment_key: notification.comment_key,
              comment_params: comment_params(notification),
            }
          end
          notifications.uniq
        end
      end

      def recipients_for_notification(notification)
        recent_notifications.select do |recip|
          recip.comment_key == notification[:comment_key]
        end
      end

      def description
        @description ||= begin
          extra_for_user = " to #{user}" if user
          "#{repository.name_with_owner} notifications#{extra_for_user}"
        end
      end

      def user_params(notification)
        current_params.merge(user: notification.user.id)
      end

      def extra_thread_info(thread_key)
        type, id = thread_key.split(";")

        if type == "Issue"
          return unless issue = Issue.find_by_id(id)
          "(##{issue.number})"
        end

        if type == "Discussion"
          return unless discussion = Discussion.find_by_id(id)
          "(##{discussion.number})"
        end
      end

      def handler_link(key = nil)
        title = key || :all
        if params[:handler] == key.to_s
          title
        elsif !(params[:handler] || key)
          title
        else
          helpers.link_to(title, handler_url(key))
        end
      end

      def before_time
        return @before_time if defined?(@before_time)
        @before_time = (timestamp = current_params[:before]) ? Time.at(timestamp.to_i) : nil
      end

      def next_page?
        recent_notifications.present?
      end

      def next_page_params
        current_params.merge(before: latest_notification.delivered_at.to_i)
      end

      private

      def recent_notifications
        return @recent_notifications if defined?(@recent_notifications)

        @recent_notifications = ActiveRecord::Base.connected_to(role: :reading) do
          recent_email_and_web_deliveries = if mobile_push_deliveries_only?
            []
          elsif user
            ::Newsies::NotificationDelivery.by_user(user, repository, email_and_web_filter_params)
          else
            ::Newsies::NotificationDelivery.by_repository(repository, email_and_web_filter_params)
          end

          recent_email_and_web_deliveries
        end
      end

      def latest_notification
        @latest_notification ||= @recent_notifications.last
      end

      def thread_params(notification)
        url_params.update(thread: notification.thread_key)
      end

      def comment_params(notification)
        thread_params(notification).update(comment: notification.comment_key)
      end

      def handler_url(key = nil)
        uri = request.fullpath.split("?").first
        params = current_params.dup
        if key
          params[:handler] = key
        else
          params.delete(:handler)
        end
        "#{uri}?#{params.to_query}"
      end

      def url_params
        user ? { user: user.id } : {}
      end

      def handler_filter
        email_and_web_filter_params[:handler]
      end

      def mobile_push_deliveries_only?
        handler_filter == "mobile-push"
      end

      def email_and_web_filter_params
        return @email_and_web_filter_params if defined?(@email_and_web_filter_params)
        @email_and_web_filter_params = current_params.merge(before: before_time).compact
      end

      def recent_mobile_push_deliveries
        []
      end

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
