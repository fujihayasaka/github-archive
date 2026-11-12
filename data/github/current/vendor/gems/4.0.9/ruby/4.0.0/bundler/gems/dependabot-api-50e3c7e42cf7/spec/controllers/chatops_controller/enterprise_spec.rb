# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :enterprise do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  it "is disabled in Enterprise installs" do
    get :list

    expect(response).to be_not_found
  end
end
