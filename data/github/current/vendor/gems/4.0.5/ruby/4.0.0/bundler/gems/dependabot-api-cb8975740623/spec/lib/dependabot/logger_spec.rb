# frozen_string_literal: true

require "rails_helper"
require "dependabot/logger"

RSpec.describe Logger do
  let(:log_output) { StringIO.new }

  before do
    Scrolls.stream = log_output
  end

  it "writes structured logs" do
    Dependabot::Logger.info(msg: "test", foo: "bar bar", foz: 1)

    expect(log_output.string.rstrip).to eq(
      'app=dependabot-api env=test msg=test foo="bar bar" foz=1 level=info'
    )
  end
end
