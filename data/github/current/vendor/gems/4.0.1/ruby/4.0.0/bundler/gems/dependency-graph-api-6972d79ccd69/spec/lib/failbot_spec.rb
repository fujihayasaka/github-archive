require "rails_helper"

context "failbot" do
  it "reports hostname" do
    expect(Failbot.context.detect { |c| c[:server] }).to_not be_nil
  end
end
