# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::Twirp::Autofix do
  describe "#create_suggested_fix_annotation" do
    it "creates an annotation on the pull request"
    it "raises NotFound when the repo is not found"
    it "raises Error when there is an error"
  end
end
