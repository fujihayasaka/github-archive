require "rails_helper"

RSpec.describe ApplicationController, type: :controller do
  controller do
    def log_something
      DependencyGraph.logger.info("log_something")
    end
  end

  describe "logging" do
    before do
      routes.draw { get "log_something" => "anonymous#log_something" }
    end

    it "includes default logging context for the request" do
      allow(DependencyGraph.logger).to receive(:with_named_tags).and_call_original
      allow(DependencyGraph.logger).to receive(:info).and_call_original

      get :log_something

      expect(DependencyGraph.logger).to have_received(:with_named_tags).with a_hash_including({
        "code.function" => "AnonymousController#log_something"
      })

      expect(DependencyGraph.logger).to have_received(:info).with "log_something"
    end
  end
end
