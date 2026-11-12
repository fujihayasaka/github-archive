# frozen_string_literal: true

require "rails_helper"

RSpec.describe SuggestedFixFile, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject(:suggested_fix_file) { FactoryBot.create(:suggested_fix_file) }

  describe "validations" do
    it { is_expected.to be_valid }

    describe "#suggested_fix" do
      it "is required" do
        suggested_fix_file.suggested_fix = nil
        expect(suggested_fix_file).not_to be_valid
      end

      it "validates multiple files may exist for a single fix" do
        first = create(:suggested_fix_file)
        second = build(:suggested_fix_file, suggested_fix: first.suggested_fix)

        expect(second).to be_valid
      end
    end

    describe "#file_path" do
      it "is required" do
        suggested_fix_file.file_path = nil
        expect(suggested_fix_file).not_to be_valid

        suggested_fix_file.file_path = ""
        expect(suggested_fix_file).not_to be_valid

        suggested_fix_file.file_path = "fake/file/path"
        expect(suggested_fix_file).to be_valid
      end
    end

    describe "#file_path_hash" do
      it "is required" do
        suggested_fix_file.file_path_hash = nil
        expect(suggested_fix_file).not_to be_valid

        suggested_fix_file.file_path_hash = ""
        expect(suggested_fix_file).not_to be_valid
      end

      it "is a SHA256 encoded in binary" do
        # Hex encoded SHA256 of "fake/file/path"
        suggested_fix_file.file_path_hash = "5ea1fcba5afee86c43f03d64edc0c380470badd69de258f2d16d67abd4b85c41="
        expect(suggested_fix_file).not_to be_valid

        # Binary encoded SHA256 of "fake/file/path"
        suggested_fix_file.file_path_hash = "\xC1\x0E$\xA8j\x95\x8C\x17m\x83\v\x9A($E\x82\xF4\xD14^\xFA4\xE3Z\x80\xBF\xAB\x05\x93\xB0\xBDn" # rubocop:disable Layout/LineLength
        expect(suggested_fix_file).to be_valid
      end
    end

    describe "#file_checksum" do
      it "is required" do
        suggested_fix_file.file_checksum = nil
        expect(suggested_fix_file).not_to be_valid

        suggested_fix_file.file_checksum = ""
        expect(suggested_fix_file).not_to be_valid
      end

      it "is a SHA1 encoded in binary" do
        # Hex encoded SHA1 of diff_content below
        suggested_fix_file.file_checksum = "6575984d0f33172dbd5ca8c57e4f66d9d22184a3"
        expect(suggested_fix_file).not_to be_valid

        # Binary encoded SHA1 of diff_content below
        suggested_fix_file.file_checksum = "eu\x98M\x0F3\x17-\xBD\\\xA8\xC5~Of\xD9\xD2!\x84\xA3"
        expect(suggested_fix_file).to be_valid
      end
    end

    describe "#diff_content" do
      it "is required" do
        suggested_fix_file.diff_content = nil
        expect(suggested_fix_file).not_to be_valid

        suggested_fix_file.diff_content = ""
        expect(suggested_fix_file).not_to be_valid

        suggested_fix_file.diff_content = "0x2D2D2D20612F696E6465782E6A730A2B2B2B20622F696E6465782E6A730A4040202D312C33202B312C342040400A207661722065787072657373203D207265717569726528276578707265737327292C0A2D202020206673203D20726571756972652827667327293B0A2B202020206673203D20726571756972652827667327292C0A2B20202020657363617065203D207265717569726528276573636170652D68746D6C27293B0A200A4040202D31302C34202B31312C342040400A20202020202020202066696C654E616D65732E666F72456163682866696C654E616D65203D3E207B0A2D2020202020202020202020202F2F204241443A206066696C654E616D65602063616E20636F6E7461696E2048544D4C20656C656D656E74730A2D2020202020202020202020206C697374202B3D20273C6C693E27202B2066696C654E616D65202B20273C2F6C693E273B0A2B2020202020202020202020202F2F20474F4F443A2065736361706564206066696C654E616D65602063616E206E6F7420636F6E7461696E2048544D4C20656C656D656E74730A2B2020202020202020202020206C697374202B3D20273C6C693E27202B206573636170652866696C654E616D6529202B20273C2F6C693E273B0A2020202020202020207D293B0A" # rubocop:disable Layout/LineLength
        expect(suggested_fix_file).to be_valid
      end
    end
  end
end
