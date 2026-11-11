require "rails_helper"

RSpec.describe ErrorsController, type: :controller do
  describe "a POST to /errors" do
    it "reports to failbot" do
      expect(Failbot).to receive(:report).with(ErrorsController::SinkError)

      post :report_error, params: { message: "oh no", backtrace: "script.rb:1:in `fake`" }
    end
  end
end
