# typed: false
# frozen_string_literal: true

require "test_helper"

class CodersRepositoryCoderTest < GitHub::TestCase
  context "#created_by_user_id" do
    test "answers ID when set with integer" do
      subject = Coders::RepositoryCoder.new
      subject.created_by_user_id = 2

      assert_equal 2, subject.created_by_user_id
    end

    test "answers ID when set with user" do
      user = build :user, id: 2
      subject = Coders::RepositoryCoder.new
      subject.created_by_user_id = user

      assert_equal 2, subject.created_by_user_id
    end
  end

  context "#deleted_at" do
    test "answers nil by default" do
      subject = Coders::RepositoryCoder.new
      assert_nil subject.deleted_at
    end

    test "answers time when set with time" do
      now = Time.current
      subject = Coders::RepositoryCoder.new
      subject.deleted_at = now

      assert_equal now, subject.deleted_at
    end

    test "answers time when set with string" do
      subject = Coders::RepositoryCoder.new
      subject.deleted_at = "2018-09-11 10:10:10 UTC"

      assert_equal Time.parse("2018-09-11 10:10:10 UTC"), subject.deleted_at
    end
  end

  context "#primary_language_name" do
    test "answers nil by default" do
      subject = Coders::RepositoryCoder.new
      assert_nil subject.primary_language_name
    end

    test "answers name when set with string" do
      subject = Coders::RepositoryCoder.new
      subject.primary_language_name = "test"

      assert_equal "test", subject.primary_language_name
    end

    test "answers name when set with language name" do
      language = LanguageName.new name: "test"
      subject = Coders::RepositoryCoder.new
      subject.primary_language_name = language

      assert_equal "test", subject.primary_language_name
    end
  end

  context "#created_for_demo_by_gh" do
    test "answers false by default" do
      subject = Coders::RepositoryCoder.new

      refute subject.created_for_demo_by_gh?
    end

    test "answers true when set with true" do
      subject = Coders::RepositoryCoder.new
      subject.created_for_demo_by_gh = true

      assert subject.created_for_demo_by_gh?
    end
  end

  context "#restorable?" do
    test "restorable? reports true by default" do
      subject = Coders::RepositoryCoder.new

      assert subject.restorable?
    end

    test "restorable? reports false if assigned" do
      subject = Coders::RepositoryCoder.new
      subject.restorable = false
      refute subject.restorable?
    end

    test "restorable? reports true if assigned" do
      subject = Coders::RepositoryCoder.new
      subject.restorable = true
      assert subject.restorable?
    end
  end
end
