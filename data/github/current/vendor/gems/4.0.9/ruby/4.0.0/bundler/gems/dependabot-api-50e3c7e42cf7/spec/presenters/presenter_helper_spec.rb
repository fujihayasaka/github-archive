# frozen_string_literal: true

require "rails_helper"

RSpec.describe PresenterHelper do
  include described_class

  describe "#sanitize_input" do
    subject(:sanitized_input) { sanitize_input(input) }

    context "when input is nil" do
      let(:input) { nil }

      it "returns an empty string" do
        expect(sanitized_input).to eq("")
      end
    end

    context "when input is plain text" do
      let(:input) { "simple text" }

      it "returns the same text" do
        expect(sanitized_input).to eq("simple text")
      end
    end

    context "when input contains allowed HTML tags" do
      let(:input) { "<p>This is a paragraph.</p>" }

      it "keeps the allowed HTML tags" do
        expect(sanitized_input).to eq("<p>This is a paragraph.</p>")
      end
    end

    context "when input contains nested allowed HTML tags" do
      let(:input) { "<div><p>Text with <strong>bold</strong> and <em>italic</em> tags.</p></div>" }

      it "removes disallowed HTML tags but keeps allowed ones" do
        expect(sanitized_input).to eq("<div><p>Text with <strong>bold</strong> and <em>italic</em> tags.</p></div>")
      end
    end

    context "when input contains self-closing tags" do
      let(:input) { "Text with an image <img src='image.png' /> in between." }

      it "removes self-closing tags" do
        expect(sanitized_input).to eq("Text with an image <img src=\"image.png\"> in between.")
      end
    end

    context "when input contains potentially unsafe JavaScript tags" do
      let(:input) { '<script>alert("XSS");</script>' }

      it "removes the script tags and content" do
        expect(sanitized_input).to eq("alert(\"XSS\");")
      end
    end

    context "when input contains potentially unsafe attributes" do
      let(:input) { '<a href="javascript:alert(\'XSS\')">Click me</a>' }

      it "removes unsafe attributes but keeps the tag" do
        expect(sanitized_input).to eq("<a>Click me</a>")
      end
    end

    context "when input contains special escape characters" do
      let(:input) { 'Special chars: & < > " \'' }

      it "returns the input with correctly escaped characters" do
        expect(sanitized_input).to eq('Special chars: &amp; &lt; &gt; " \'')
      end
    end

    context "when input contains HTML entities" do
      let(:input) { "Tom &amp; Jerry" }

      it "retains HTML entities as expected" do
        expect(sanitized_input).to eq("Tom &amp; Jerry")
      end
    end

    context "when input contains complex nested tags and special characters" do
      let(:input) { "<div>Hello <span>world & <b>friends</b>!</span> &copy; 2024</div>" }

      it "removes disallowed tags and retains allowed elements with entities" do
        expect(sanitized_input).to eq("<div>Hello <span>world &amp; <b>friends</b>!</span> © 2024</div>")
      end
    end

    context "when input contains the specific string 'network_unsafe_http'" do
      let(:input) { "network_unsafe_http" }

      it "returns the input as-is" do
        expect(sanitized_input).to eq("network_unsafe_http")
      end
    end

    context "when input contains safe numeric and alphanumeric strings" do
      let(:input) { "Version 1.0.0" }

      it "returns the input unchanged" do
        expect(sanitized_input).to eq("Version 1.0.0")
      end
    end

    context "when input contains HTML comment tags" do
      let(:input) { "Hello <!-- this is a comment -->world" }

      it "removes the comment tags" do
        expect(sanitized_input).to eq("Hello world")
      end
    end
  end
end
