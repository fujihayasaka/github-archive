# typed: true
# frozen_string_literal: true

require "test_helper"

class EmailSpellcheckerTest < GitHub::TestCase
  context ".suggestion_for" do
    test "provides suggestion for gmail.com misspelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@gmail.con")
      assert_equal suggestion, "defunkt@gmail.com"
    end

    test "does not provide suggestion for correct gmail.com spelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@gmail.com")
      assert_nil suggestion
    end

    test "suggestions are case insensitive" do
      suggestion = EmailSpellchecker.suggestion_for("DEFUNKT@GMAIL.CON")
      assert_equal suggestion, "DEFUNKT@gmail.com"
    end

    test "provides suggestion for qq.com misspelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@qg.com")
      assert_equal suggestion, "defunkt@qq.com"
    end

    test "does not provide suggestion for correct qq.com spelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@qq.com")
      assert_nil suggestion
    end

    test "provides suggestion for hotmail.com misspelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@htmail.com")
      assert_equal suggestion, "defunkt@hotmail.com"
    end

    test "does not provide suggestion for correct hotmail.com spelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@hotmail.com")
      assert_nil suggestion
    end

    test "provides suggestion for outlook.com misspelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@outloook.com")
      assert_equal suggestion, "defunkt@outlook.com"
    end

    test "does not provide suggestion for correct outlook.com spelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@outlook.com")
      assert_nil suggestion
    end

    test "provides suggestion for 163.com misspelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@16.com")
      assert_equal suggestion, "defunkt@163.com"
    end

    test "does not provide suggestion for correct 163.com spelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@163.com")
      assert_nil suggestion
    end

    test "provides suggestion for yahoo.com misspelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@yahooo.com")
      assert_equal suggestion, "defunkt@yahoo.com"
    end

    test "does not provide suggestion for correct yahoo.com spelling" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@yahoo.com")
      assert_nil suggestion
    end

    test "does not provide suggestion for string without an @" do
      suggestion = EmailSpellchecker.suggestion_for("defunktgmail.con")
      assert_nil suggestion
    end

    test "does not provide suggestion for unrecognized email domain" do
      suggestion = EmailSpellchecker.suggestion_for("defunkt@github.com")
      assert_nil suggestion
    end
  end
end
