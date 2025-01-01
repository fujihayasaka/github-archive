# typed: true
# frozen_string_literal: true

require "test_helper"

class SpecimenTest < GitHub::TestCase
  context "has_repeated_links" do
    test "detects repeated links to same URL" do
      data = "<a href='toot'>foo</a> And then blah blah <span><A href='puddle'> yo</A> <div><span><em><i><a href='toot'>nark</a></i></em><div><A href='four'>blob</A>nap nap npap</div>"
      specimen = Spam::Specimen.new(data)
      assert specimen.has_repeated_links?
    end

    test "respects minimum value param" do
      data = "<a href='toot'>foo</a>  <span><A href='toot'> yo</A> <div><span><em><i><a href='toot'>nark</a></i></em><div><A href='four'>blob</A></div>"
      specimen = Spam::Specimen.new(data)
      assert specimen.has_repeated_links?(2)
      refute specimen.has_repeated_links?(3)
    end

    test "doesn't object to multiple links to different URLS" do
      data = "<a href='tooot'>foo</a> And then blah blah <span><A href='puddle'> yo ferg</A> <B>fleem</b> wobbly poo <p> shack</p><div><span><em><i><a href='burp'>nark</a></i></em><div><A href='four'>blob</A>nap nap npap</div>"
      specimen = Spam::Specimen.new(data)
      refute specimen.has_repeated_links?
    end
    test "ignores anchor links" do
      data = "<a href='#puddle'>foo</a> And then <span><A href='#puddle'> yo </A> <p> word </p> <a href='#puddle'>nark</a> <A href='four'>blob</A>"
      specimen = Spam::Specimen.new(data)
      refute specimen.has_repeated_links?
    end
  end

  context "#text" do
    test "returns the correct text for fully-embedded text" do
      data = "<b>f</b><c>lo</c><i>o</i><fff>d</fff>"
      specimen = Spam::Specimen.new(data)
      assert_equal "flood", specimen.text
    end

    test "returns the correct text for partly-embedded text" do
      data = "fl<ff>oo</ff>d"
      specimen = Spam::Specimen.new(data)
      assert_equal "flood", specimen.text
    end

    test "returns the correct text for deeply-embedded text" do
      data = "fl<ff>o<z><y>o</y></z></ff>d"
      specimen = Spam::Specimen.new(data)
      assert_equal "flood", specimen.text
    end

    test "returns the correct text for multi-word embedded text" do
      data = "<placeholder class=\"border\">#<a href=\"https://www.google.com/fusiontables/DataSource?docid=1xs3bTtK55ceA5Jyk9IsELBe1ruYEKZj7MKQo9xUn\"><K!%K>g</K!%K><K!%K>a</K!%K><K!%K>l</K!%K><K!%K>a</K!%K><K!%K>t</K!%K><K!%K>a</K!%K><K!%K>s</K!%K><K!%K>a</K!%K><K!%K>r</K!%K><K!%K>a</K!%K><K!%K>y</K!%K> <K!%K>o</K!%K><K!%K>s</K!%K><K!%K>m</K!%K><K!%K>a</K!%K><K!%K>n</K!%K><K!%K>l</K!%K><K!%K>ı</K!%K><K!%K>s</K!%K><K!%K>p</K!%K><K!%K>o</K!%K><K!%K>r</K!%K> <K!%K>m</K!%K><K!%K>a</K!%K><K!%K>ç</K!%K><K!%K>ı</K!%K> <K!%K>c</K!%K><K!%K>a</K!%K><K!%K>n</K!%K><K!%K>l</K!%K><K!%K>ı</K!%K> <K!%K>i</K!%K><K!%K>z</K!%K><K!%K>l</K!%K><K!%K>e</K!%K></a></placeholder>"
      specimen = Spam::Specimen.new(data)
      assert_equal "#galatasaray osmanlispor maci canli izle", specimen.text
    end

    test "doesn't raise when evaluating an invalid HTML-escaped char" do
      expected = "&#xFFFE;"

      specimen = Spam::Specimen.new(expected)
      assert_equal "�", specimen.text
    end
  end

  context "uses_spacing_tricks?" do
    test "catches leading encoded nbsp sequence in ASCII-8BIT" do
      specimen = Spam::Specimen.new("\xC2\xA0\n" * (Spam::Node::LEADING_NBSP_LIMIT + 1))
      assert specimen.uses_spacing_tricks?
    end

    test "isn't too aggressive with leading nbsp sequence" do
      specimen = Spam::Specimen.new("\xC2\xA0\n" * Spam::Node::LEADING_NBSP_LIMIT)
      refute specimen.uses_spacing_tricks?
    end

    test "catches leading encoded nbsp sequence in UTF-8" do
      specimen = Spam::Specimen.new("\u00A0\n" * (Spam::Node::LEADING_NBSP_LIMIT + 1))
      assert specimen.uses_spacing_tricks?
    end

    test "catches excessive trailing <br/> use" do
      specimen = Spam::Specimen.new("foo " + "<br>" * (Spam::Node::TRAILING_BR_LIMIT + 1))
      assert specimen.uses_spacing_tricks?
    end

    test "handles trailing <br> (without /)" do
      specimen = Spam::Specimen.new("foo " + "<br>" * (Spam::Node::TRAILING_BR_LIMIT + 1))
      assert specimen.uses_spacing_tricks?
    end

    test "isn't too aggressive with trailing <br> use" do
      specimen = Spam::Specimen.new("foo " + "<br>" * (Spam::Node::TRAILING_BR_LIMIT - 1))
      refute specimen.uses_spacing_tricks?
    end
  end
end
