# typed: true
# frozen_string_literal: true

require "tempfile"
require "test_helper"

class DocsUrlConfigTest < GitHub::TestCase

  def with_temp_json_file(content)
    file = Tempfile.new("docs.json")
    file.write(content)
    file.close
    begin
      yield file
    ensure
      file.unlink
    end
  end

  def with_temp_instance(content)
    with_temp_json_file(content) do |file|
      yield DocsUrlConfig.new(file.path)
    end
  end


  test "identifier found" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url}/fooing/baring", instance.url_for("foo/bar")
    end
  end

  test "enterprise cloud prefix" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url(skip_enterprise: true, ghec_exclusive: true)}/fooing/baring", instance.url_for("foo/bar", ghec: true)
    end
  end

  test "json file is only read once" do
    file = Tempfile.new("urls.json")
    file.write('{"foo": "/foo"}')
    file.close
    begin
      instance = DocsUrlConfig.new(T.must(file.path))
      assert_equal "#{GitHub.help_url}/foo", instance.url_for("foo")
    ensure
      file.unlink
    end
    # Still! Even though the .json file is deleted now
    assert_equal "#{GitHub.help_url}/foo", instance.url_for("foo")
  end

  test "identifier missing" do
    with_temp_instance('{"foo": "/foo"}') do |instance|
      assert_raises(DocsUrlConfig::IdentifierError) do
        instance.url_for("neverheardof")
      end
    end
  end

  test "json file doesn't exist" do
    assert_raises(DocsUrlConfig::JSONConfigFileError) do
      DocsUrlConfig.new("blabla.json").url_for("anything")
    end
  end

  test "json file has to be valid JSON" do
    with_temp_json_file("This is not JSON") do |file|
      assert_raises(DocsUrlConfig::JSONConfigParseError) do
        DocsUrlConfig.new(file.path).url_for("anything")
      end
    end
  end

  test "return full URL with simple query value" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url}/fooing/baring?tool=vscode", instance.url_for("foo/bar", query: { tool: "vscode" })
    end
  end

  test "return full URL with escapable query value" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url}/fooing/baring?tool=%3F%20%26%20%3D%20%23", instance.url_for("foo/bar", query: { tool: "? & = #" })
    end
  end

  test "return full URL with query value that is an integer" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url}/fooing/baring?one=1", instance.url_for("foo/bar", query: { one: 1 })
    end
  end

  test "return full URL with fragment" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url}/fooing/baring#%C3%A5", instance.url_for("foo/bar", fragment: "å")
    end
  end

  test "return full URL with query and fragment" do
    with_temp_instance('{"foo/bar": "/fooing/baring"}') do |instance|
      assert_equal "#{GitHub.help_url}/fooing/baring?a=A#%C3%A5", instance.url_for("foo/bar", query: { a: "A" }, fragment: "å")
    end
  end
end
