# typed: true
# frozen_string_literal: true

require "test_helper"

class Forks::ForksControllerDependencyTest < GitHub::TestCase
  def set_user_default_options(**options)
    user_settings = T.cast(UserSettings.create!(user: @user), T.untyped)
    user_settings.set!(:forks_view_default_options, options.to_json)
    @user.reload
  end

  class HelperTestHelper < FakeHelper
    attr_reader :current_user

    def initialize(user)
      @current_user = user
    end

    def user_or_global_feature_enabled?(feature_name)
      GitHub.flipper[feature_name].enabled? || GitHub.flipper[feature_name].enabled?(current_user)
    end
  end

  setup do
    @user = create(:user)
    @helper = HelperTestHelper.new(@user)
    @helper.extend Forks::ForksControllerDependency
  end

  def assert_default_options_for_anonymous(persisted:)
    options = @helper.safe_options_resolver
    assert_equal [:active], options.include
    assert_equal "2y", options.period
    assert_equal :stargazer_counts, options.sort_by
    if persisted
      assert_predicate options, :persisted?
    else
      refute_predicate options, :persisted?
    end
  end

  context "#safe_options_resolver" do
    context "when :forks_view_user_default_options is enabled" do
      context "when a user has default options" do
        context "and no params are provided" do
          test "it seeds the default options" do
            GitHub.flipper[:forks_view_user_default_options].enable
            @helper.current_user = @user
            set_user_default_options(
              include: "active,network,archived",
              sort_by: "stargazer_counts",
              period: "5y",
            )

            assert_equal [:active, :archived, :network], @helper.safe_options_resolver.include
            assert_equal :stargazer_counts, @helper.safe_options_resolver.sort_by
            assert_equal "5y", @helper.safe_options_resolver.period
            assert @helper.safe_options_resolver.persisted?
          end
        end

        context "and other params are provided" do
          test "it merges the defaults with the params" do
            GitHub.flipper[:forks_view_user_default_options].enable
            set_user_default_options(include: "active,network,archived", sort_by: "stargazer_counts")
            @helper.current_user = @user
            @helper.params[:sort_by] = "open_issue_counts"

            assert_equal [:active, :archived, :network], @helper.safe_options_resolver.include
            assert_equal :open_issue_counts, @helper.safe_options_resolver.sort_by
            refute @helper.safe_options_resolver.persisted?
          end
        end
      end

      context "when no user is signed in" do
        test "it uses the default options" do
          GitHub.flipper[:forks_view_user_default_options].enable
          assert_default_options_for_anonymous(persisted: true)
        end
      end
    end

    context "when :forks_view_user_default_options is disabled" do
      context "when no user is signed in" do
        test "it uses the default options" do
          GitHub.flipper[:forks_view_user_default_options].disable
          assert_default_options_for_anonymous(persisted: false)
        end

        test "it merges defaults with provided params" do
          @helper.params[:sort_by] = "open_issue_counts"
          assert_equal :open_issue_counts, @helper.safe_options_resolver.sort_by
        end
      end

      context "when a user has default options" do # In case the flag is disabled before shipping
        test "it uses coded defaults, and not the user-set defaults" do
          GitHub.flipper[:forks_view_user_default_options].disable
          @helper.current_user = @user
          set_user_default_options(sort_by: "open_issue_counts")

          assert_equal :stargazer_counts, @helper.safe_options_resolver.sort_by
        end
      end
    end
  end
end
