# frozen_string_literal: true

require "rails_helper"
require "dependabot/request_logger"

RSpec.describe Dependabot::RequestLogger, type: :request do
  subject { log_output.string }

  let(:log_output) { StringIO.new }
  let(:headers) { {} }
  let(:request_path) { "/non-existent-path" }

  before do
    Scrolls.stream = log_output
    get request_path, headers: headers
  end

  it { is_expected.to match(/request_id=[^ ]+/) }
  it { is_expected.to include("request_method=get") }
  it { is_expected.to include("path_info=\"#{request_path}\"") }

  context "with X-GitHub-Request-Id header" do
    let(:headers) do
      { Dependabot::RequestLogger::X_REQUEST_ID => "1234" }
    end

    it { is_expected.to include("request_id=1234") }
  end

  context "when the path cannot be routed" do
    let(:request_path) { "/non-existent-path" }

    it { is_expected.to include("path_info=\"#{request_path}\"") }
    it { is_expected.to include("status=404") }
  end

  context "when logging health checks outside of enterprise mode", :cloud do
    let(:request_path) { "/_ping" }

    it { is_expected.to match(/request_id=[^ ]+/) }
    it { is_expected.to include("request_method=get") }
    it { is_expected.to include("path_info=\"#{request_path}\"") }
    it { is_expected.to include("status=200") }
  end

  context "when logging health checks in enterprise mode", :enterprise do
    let(:request_path) { "/_ping" }

    it { is_expected.to be_blank }
  end
end
