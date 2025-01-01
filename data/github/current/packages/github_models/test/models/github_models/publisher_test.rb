# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::PublisherTest < GitHub::TestCase
  context "validations" do
    test "it is valid when it has a name and logo url" do
      publisher = build(:github_models_publisher)
      assert(publisher.valid?)
    end

    test "it is not valid when missing a name" do
      publisher = build(:github_models_publisher, name: nil)
      refute publisher.valid?
    end

    test "it is not valid when the name is too long" do
      publisher = build(:github_models_publisher, name: ("a" * 70))
      refute publisher.valid?
    end

    test "it is not valid when the name not unique" do
      create(:github_models_publisher, name: "Microsoft")
      publisher = build(:github_models_publisher, name: "Microsoft")
      refute publisher.valid?
    end
  end
end
