# typed: true
# frozen_string_literal: true

require "test_helper"

class CWETest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @cwe1 = create(:cwe, cwe_id: "CWE-7", name: "Cross site1")
    @cwe2 = create(:cwe, cwe_id: "CWE-8", name: "cross site2")
    @cwe3 = create(:cwe, cwe_id: "CWE-17", name: "buffer overflow")
  end

  context "validation" do
    test "requires a valid cwe_id" do
      cwe = CWE.new(name: "foo", description: "bar")
      refute_predicate cwe, :valid?
      refute_empty cwe.errors[:cwe_id]

      cwe = CWE.new(cwe_id: "CWE-", name: "foo", description: "bar")
      refute_predicate cwe, :valid?
      refute_empty cwe.errors[:cwe_id]

      cwe = CWE.new(cwe_id: "CWE-1A3", name: "foo", description: "bar")
      refute_predicate cwe, :valid?
      refute_empty cwe.errors[:cwe_id]

      cwe = CWE.new(cwe_id: "CWE-123456", name: "foo", description: "bar")
      refute_predicate cwe, :valid?
      refute_empty cwe.errors[:cwe_id]

      cwe = CWE.new(cwe_id: "CWE-1", name: "foo", description: "bar")
      assert_predicate cwe, :valid?

      cwe = CWE.new(cwe_id: "CWE-12345", name: "foo", description: "bar")
      assert_predicate cwe, :valid?
    end

    test "requires a valid name" do
      cwe = CWE.new(cwe_id: "CWE-1", name: "", description: "bar")

      refute_predicate cwe, :valid?
      refute_empty cwe.errors[:name]
    end

    test "requires a valid description" do
      cwe = CWE.new(cwe_id: "CWE-1", name: "foo", description: "")

      refute_predicate cwe, :valid?
      refute_empty cwe.errors[:description]
    end
  end

  context "with_content_like scope" do
    test "searches by name case insensitively" do
      cwes = CWE.order(id: :asc).with_content_like("cross")
      assert_equal [@cwe1, @cwe2], cwes

      cwes = CWE.order(id: :asc).with_content_like("o")
      assert_equal [@cwe1, @cwe2, @cwe3], cwes
    end

    test "searches by CWE id" do
      cwes = CWE.order(id: :asc).with_content_like("7")
      assert_equal [@cwe1, @cwe3], cwes

      cwes = CWE.order(id: :asc).with_content_like("CWE-")
      assert_equal [@cwe1, @cwe2, @cwe3], cwes
    end
  end

  [:name, :description].each do |field|
    test "supports emoji for #{field}" do
      cwe = create(:cwe, field => "we ❤️ emojis")

      assert_multibyte_tracked_changes(cwe, field)
    end
  end
end
