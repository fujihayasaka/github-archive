# typed: true
# frozen_string_literal: true

require "test_helper"

class UserLanguagesTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "pro"
    @js   = create :language_name, name: "JavaScript", linguist_id: 183
    @ruby = create :language_name, name: "Ruby", linguist_id: 326
  end

  context "#calculate_primary_language!" do
    test "returns nil if the user doesn't own any repos" do
      assert_empty @user.repositories
      assert_nil @user.calculate_primary_language!
    end

    test "returns nil if the user doesn't own any public repos" do
      create :private_repository, owner: @user
      refute_empty @user.repositories.private_scope
      assert_empty @user.repositories.public_scope

      assert_nil @user.calculate_primary_language!
    end

    test "returns nil if the user does not have any active public repos" do
      create :repository, active: nil, owner: @user
      assert_empty @user.repositories.public_scope.active

      assert_nil @user.calculate_primary_language!
    end

    test "returns the LanguageName for the user's repository" do
      repo = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_js
      repo.analyze_languages

      assert_equal @js, @user.calculate_primary_language!
    end

    test "returns the most common language from the set of user's repositories" do
      js_repo = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_js

      ruby_repo_1 = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_ruby_1

      ruby_repo_2 = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_ruby_2

      [js_repo, ruby_repo_1, ruby_repo_2].each { |r| r.analyze_languages }

      assert_equal @ruby, @user.calculate_primary_language!
    end

    test "persists the user's primary language" do
      assert_nil @user.primary_language_name_id

      repo = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_js
      repo.analyze_languages

      @user.calculate_primary_language!
      assert_equal @js.id, @user.reload.primary_language_name_id
    end
  end

  context "#primary_language" do
    test "returns the user's primary language if it has already been calculated" do
      repo = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_js
      repo.analyze_languages

      @user.calculate_primary_language!
      refute_nil @user.reload.primary_language_name_id

      @user.expects(:calculate_primary_language!).never
      assert_equal @js, @user.primary_language
    end

    test "computes the user's primary language if it hasn't been persisted" do
      repo = create :repository, owner: @user, created_at: 1.day.ago, pushed_at: 1.hour.ago, from_example: :language_js
      repo.analyze_languages

      assert_nil @user.primary_language_name_id

      assert_equal @js, @user.primary_language

      refute_nil @user.reload.primary_language_name_id
    end
  end

  context "#repo_language_breakdown" do
    test "returns a list of the primary languages with the nunmber of repos" do
      create :repository, owner: @user, primary_language_name_id: @ruby.id
      create :repository, owner: @user, primary_language_name_id: @js.id
      create :repository, owner: @user, primary_language_name_id: @js.id
      langs = @user.repo_language_breakdown(@user.repositories, 5)
      assert_equal({ "JavaScript" => 2, "Ruby" => 1 }, langs)
      langs = @user.repo_language_breakdown(@user.repositories, 1)
      assert_equal({ "JavaScript" => 2 }, langs)
    end
  end

  context "#repo_id_language_breakdown" do
    test "returns a list of the primary languages with the nunmber of repos" do
      create :repository, owner: @user, primary_language_name_id: @ruby.id
      create :repository, owner: @user, primary_language_name_id: @js.id
      create :repository, owner: @user, primary_language_name_id: @js.id
      langs = @user.repo_id_language_breakdown(@user.repositories.pluck(:id), 5)
      assert_equal({ "JavaScript" => 2, "Ruby" => 1 }, langs)
      langs = @user.repo_id_language_breakdown(@user.repositories.pluck(:id), 1)
      assert_equal({ "JavaScript" => 2 }, langs)
    end
  end
end
