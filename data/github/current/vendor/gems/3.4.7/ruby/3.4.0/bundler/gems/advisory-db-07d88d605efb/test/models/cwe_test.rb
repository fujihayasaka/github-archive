# frozen_string_literal: true

require "test_helper"

class CWETest < ActiveSupport::TestCase
  test "can create a CWE" do
    CWE.create!(cwe_id: "CWE-79", name: "Improper Neutralization of Input During Web Page Generation ('Cross-site Scripting')")
    new_cwe = CWE.last

    assert_equal "CWE-79", new_cwe.cwe_id
    assert_equal "Improper Neutralization of Input During Web Page Generation ('Cross-site Scripting')", new_cwe.name
  end

  test "cannot create a CWE without a name" do
    assert_raises(ActiveRecord::RecordInvalid) do
      CWE.create!(cwe_id: "CWE-179", name: "")
    end
  end
end
