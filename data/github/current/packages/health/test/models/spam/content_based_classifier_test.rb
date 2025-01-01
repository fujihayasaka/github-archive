# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamContentBasedClassifierTest < GitHub::TestCase
  def content_based_classifier_stub
    spam = { spam: 0.6, ham: 0.4 }

    request_stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("/v1/predict?model=gist") do |_env|
        [200, {}, JSON.dump(spam)]
      end

      stub.post("/v1/predict?model=issue_comment") do |_env|
        [413, {}, "<html><head>Title</head><body></body></html>"]
      end
    end

    Faraday.new(url: "http://example.invalid") do |builder|
      builder.adapter :test, request_stubs do |_stub|
      end
    end
  end

  setup do
    Spam::ContentBasedClassifier.any_instance.stubs(:connection).returns(content_based_classifier_stub)
    Spam::ContentBasedClassifier.any_instance.stubs(:create_issue)
    Spam::ContentBasedClassifier.any_instance.stubs(:disable!)
  end

  context "#classify" do
    test "classifies a string of text as spam or ham" do
      classifier = Spam::ContentBasedClassifier.new
      result = classifier.classify(html: "some plain text spam", model_name: "Gist")
      assert_equal 0.6, result["spam"]
      assert_equal 0.4, result["ham"]
    end

    test "uses fallback for failed request" do
      classifier = Spam::ContentBasedClassifier.new
      result = classifier.classify(html: "some plain text spam", model_name: "foo")
      assert_equal 0.5, result["spam"]
      assert_equal 0.5, result["ham"]
    end
  end

  context "#connection" do
    test "returns a Faraday connection" do
      classifier = Spam::ContentBasedClassifier.new
      assert_kind_of Faraday::Connection, classifier.connection
    end
  end
end
