require "rails_helper"

describe DependencyGraph do
  context "#rails_cache_error_handler" do
    it "returns a proper error handler for the rails cache" do
      expect(Instrument).to receive(:increment).with("rails_cache.error", error_class: "standard_error")
      expect(DependencyGraph.logger).to receive(:error)

      DependencyGraph.rails_cache_error_handler.call(
        method: "call",
        returning: nil,
        exception: StandardError.new("New error!")
      )
    end
  end
end
