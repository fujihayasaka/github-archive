# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class NotificationDeliveryTest < GitHub::TestCase
    include NewsiesHelper

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @repo = create(:repository)
      @issue = create(:issue, repository: @repo)

      @newsies_list = Newsies::List.to_object(@repo)
      @newsies_thread = Newsies::Thread.to_object(@issue, list: @newsies_list)
      @newsies_comment = Newsies::Comment.to_object(@issue)

      @users = create_list(:user, 3, :verified)
      @owner = @repo.owner

      (@users + [@owner]).each { |user| enable_notifications_for_user(user) }

      GitHub.newsies.subscribe_to_list(@users.first, @repo)
    end

    setup do
      ActionMailer::Base.deliveries.clear
      GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
    end

    test "is readonly" do
      assert_performed_with job: SubscribeAndNotifyJob do
        create :issue, repository: @repo, user: @owner
      end

      assert_raises ActiveRecord::ReadOnlyRecord do
        notification = NotificationDelivery.first
        T.must(notification).update!({ user_id: 12345 })
      end
    end

    test "doesn't muck up timezones" do
      t1 = Time.now.to_i
      assert_performed_with job: SubscribeAndNotifyJob do
        create :issue, repository: @repo, user: @owner
      end
      t2 = Time.now.to_i

      delivery = NotificationDelivery.by_user(@users.first, @repo).first

      assert (t1..t2).cover?(delivery.delivered_at.to_i)
    end

    context ".handler_data" do
      test "returns an empty hash if there aren't any tracked deliveries" do
        assert_empty NotificationDelivery.handler_data(
          @newsies_list.id,
          @newsies_thread.key,
          @newsies_comment.key,
          @users.map(&:id),
        )
      end

      test "returns delivery data indexed by user IDs" do
        user_ids_to_handlers = {
          @users.second.id => [
            %w[web mentioned],
            %w[email list],
          ],
          @users.third.id => [
            %w[web assigned],
          ],
        }
        NotificationDelivery.batch_create_from_handler_data(
          @newsies_list.id,
          @newsies_thread.key,
          @newsies_comment.key,
          user_ids_to_handlers,
        )

        assert_equal(
          {
            @users.second.id => {
              "web" => "mentioned",
              "email" => "list",
            },
            @users.third.id => {
              "web" => "assigned",
            },
          },
          NotificationDelivery.handler_data(
            @newsies_list.id,
            @newsies_thread.key,
            @newsies_comment.key,
            @users.map(&:id),
          ),
        )
      end
    end

    context ".batch_create_from_handler_data" do
      test "batch inserts deliveries provided in a hash" do
        user_ids_to_handlers = {
          @users.second.id => [
            %w[web mentioned],
            %w[email list],
          ],
          @users.third.id => [
            %w[web assigned],
          ],
        }

        refute NotificationDelivery.exists?

        NotificationDelivery.batch_create_from_handler_data(
          @newsies_list.id,
          @newsies_thread.key,
          @newsies_comment.key,
          user_ids_to_handlers,
        )

        scope = NotificationDelivery.where(
          list_id: @newsies_list.id,
          thread_key: @newsies_thread.key,
          comment_key: @newsies_comment.key,
        )

        assert_equal 3, NotificationDelivery.count
        assert scope.where(user_id: @users.second.id, handler: "web", reason: "mentioned").exists?
        assert scope.where(user_id: @users.second.id, handler: "email", reason: "list").exists?
        assert scope.where(user_id: @users.third.id, handler: "web", reason: "assigned").exists?
      end

      test "does not insert web handler deliveries for repository watchers" do
        user_ids_to_handlers = {
          @users.first.id => [
            %w[web list],
            %w[email list],
          ],
          @users.second.id => [
            %w[web assigned],
          ],
          @users.third => [
            %w[web list],
          ],
        }

        refute NotificationDelivery.exists?

        NotificationDelivery.batch_create_from_handler_data(
          @newsies_list.id,
          @newsies_thread.key,
          @newsies_comment.key,
          user_ids_to_handlers,
        )

        scope = NotificationDelivery.where(
          list_id: @newsies_list.id,
          thread_key: @newsies_thread.key,
          comment_key: @newsies_comment.key,
        )

        assert_equal 2, NotificationDelivery.count

        refute scope.where(user_id: @users.first.id, handler: "web", reason: "list").exists?
        assert scope.where(user_id: @users.first.id, handler: "email", reason: "list").exists?
        assert scope.where(user_id: @users.second.id, handler: "web", reason: "assigned").exists?
        refute scope.where(user_id: @users.third.id, handler: "web", reason: "list").exists?
      end
    end
  end
end
