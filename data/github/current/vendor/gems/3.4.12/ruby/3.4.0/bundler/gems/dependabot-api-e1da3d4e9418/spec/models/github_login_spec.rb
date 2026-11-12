# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHubLogin do
  describe "#type" do
    it "is :string" do
      expect(described_class.new.type).to eq(:string)
    end
  end

  describe "#cast" do
    context "when in Proxima", :proxima do
      it "removes shortcodes" do
        login = "monalisa"
        shortcode = "_github"
        login_with_shortcode = "#{login}#{shortcode}"

        expect(described_class.new.cast(login_with_shortcode)).to eq(login)
      end
    end

    context "when in non-Proxima environments", :cloud, :enterprise do
      it "returns the login as-is" do
        login = "monalisa"
        shortcode = "_github"
        login_with_shortcode = "#{login}#{shortcode}"

        expect(described_class.new.cast(login_with_shortcode)).to eq(login_with_shortcode)
      end
    end
  end

  describe "#serialize" do
    context "when in Proxima", :proxima do
      it "removes shortcodes" do
        login = "monalisa"
        shortcode = "_github"
        login_with_shortcode = "#{login}#{shortcode}"

        expect(described_class.new.serialize(login_with_shortcode)).to eq(login)
      end
    end

    context "when in non-Proxima environments", :cloud, :enterprise do
      it "returns the login as-is" do
        login = "monalisa"
        shortcode = "_github"
        login_with_shortcode = "#{login}#{shortcode}"

        expect(described_class.new.serialize(login_with_shortcode)).to eq(login_with_shortcode)
      end
    end
  end

  describe "#deserialize" do
    context "when in Proxima", :proxima do
      it "removes shortcodes" do
        login = "monalisa"
        shortcode = "_github"
        login_with_shortcode = "#{login}#{shortcode}"

        expect(described_class.new.deserialize(login_with_shortcode)).to eq(login)
      end
    end

    context "when in non-Proxima environments", :cloud, :enterprise do
      it "returns the login as-is" do
        login = "monalisa"
        shortcode = "_github"
        login_with_shortcode = "#{login}#{shortcode}"

        expect(described_class.new.deserialize(login_with_shortcode)).to eq(login_with_shortcode)
      end
    end
  end
end
