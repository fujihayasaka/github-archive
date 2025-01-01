require "spec_helper"
require "active_support"
require "active_support/core_ext"

require_relative "../../lib/configuration"

describe Configuration do
  describe ".build" do
    it "returns a configuration" do
      config = Configuration.build({ abc: "456" })
      expect(config.abc).to eq "456"
    end

    it "validates required keys" do
      expect {
        Configuration.build({ abc: true }, {
          require: :abc
        })
      }.to_not raise_error

      expect {
        Configuration.build({ abc: true }, {
          require: :def
        })
      }.to raise_error(Configuration::MissingKeysError)
    end

    it "accepts defaults" do
      config = Configuration.build({ abc: "456" }, {
        defaults: {
          def: "789"
        }
      })

      expect(config.abc).to eq "456"
      expect(config.def).to eq "789"
    end
  end
end
