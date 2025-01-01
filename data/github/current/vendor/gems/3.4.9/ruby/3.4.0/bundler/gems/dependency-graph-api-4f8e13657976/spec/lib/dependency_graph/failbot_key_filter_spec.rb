# frozen_string_literal: true
require_relative "../../../lib/dependency_graph/failbot_key_filter"
require_relative "../../../lib/dependency_graph_api"

describe DependencyGraph::FailbotKeyFilter do
  if DependencyGraphAPI.enterprise?
    it "returns the same context" do
      filter = DependencyGraph::FailbotKeyFilter.new
      context = filter.call({ server: "localhost", personal_data: "bad" })
      expected = { server: "localhost", personal_data: "bad" }
      expect(expected).to eq(context)
    end
  else
    it "returns a context" do
      filter = DependencyGraph::FailbotKeyFilter.new
      context = filter.call({})
      expect(context).not_to eq(nil)
    end

    it "removes keys not on allowed list" do
      filter = DependencyGraph::FailbotKeyFilter.new
      context = filter.call({ server: "localhost", personal_data: "bad" })
      expected = { server: "localhost" }
      expect(expected).to eq(context)
    end

    it "allows keys from tagger" do
      # pick first key not in allow list that is in tagger:
      tag_name = (DependencyGraph::TAGGED_SENTRY_KEYS - DependencyGraph::ALLOWED_SENTRY_KEYS)[0]
      filter = DependencyGraph::FailbotKeyFilter.new
      hash = {}
      tag_name_sym = tag_name.to_sym
      hash[tag_name_sym] = "some_value"
      context = filter.call(hash)
      expect(context[tag_name_sym]).to eq("some_value")
    end

    it "removes keys prefixed with a hash" do
      filter = DependencyGraph::FailbotKeyFilter.new
      context = filter.call({ "#server" => "data", "#personal_data" => "bad" })
      expected = { "#server" => "data" }
      expect(expected).to eq(context)
    end

    it "removes string keys" do
      filter = DependencyGraph::FailbotKeyFilter.new
      context = filter.call({ "server" => "localhost", "personal_data" => "bad" })
      expected = { "server" => "localhost" }
      expect(expected).to eq(context)
    end

    it "removes symbol keys" do
      filter = DependencyGraph::FailbotKeyFilter.new
      context = filter.call({ server: "localhost", personal_data: "bad" })
      expected = { server: "localhost" }
      expect(expected).to eq(context)
    end
  end
end
